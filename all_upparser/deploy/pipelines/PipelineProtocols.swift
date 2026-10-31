//
//  Custom Protocols and Extensions and Services that pipelines use
//  Tagger
//
//  Created by Adam on 20/10/2026.
//

import Foundation
import CoreML

//MARK: 1 : protocols + extensions
//1 pipeline loader : keep loader stuff separate

//enum of helper structs
enum BERTpipeHelperStructs{
    struct LabelVocabs {
    // MARK: - Label vocabularies for BERT derived models :: 4x vocabs with loader
    /// The  vocabularies that turn output indices back into labels, from same training as model
    /// these are not the same as for BiLSTM models
        let upos: Vocab
        let feats: Vocab
        let deprel: Vocab
        let lemmaRule: Vocab
    }
    
    struct LogitReader {
    // MARK: - Reading Core ML output arrays for bert-derived models to deal with padding
    /// Reads values out of an MLMultiArray without boxing every element. Honours the array's
    /// strides (Core ML may pad rows) and its element type (the model's outputs are normally
    /// float16; float32 and double are handled too).

        private let array: MLMultiArray             // keeps the buffer alive
        private let base: UnsafeRawPointer
        private let dataType: MLMultiArrayDataType
        private let strides: [Int]
        private let shape: [Int]

        /// - Parameters:
        ///   - rank: expected number of dimensions (3 = [1, rows, width], 4 = [1, channels, rows, columns])
        ///   - rows: how many rows the caller will read (words + 1)
        ///   - labels: the vocabulary size this array's label dimension must match (nil to skip)
        init(_ output: MLFeatureProvider, _ name: String, rank: Int, rows: Int,
             labels: Int? = nil) throws  {
            guard let array = output.featureValue(for: name)?.multiArrayValue else {
                throw PipelineError.GenericError.unexpectedOutput("\(name) is missing")
            }

            let shape = array.shape.map { $0.intValue }
            guard shape.count == rank, shape[rank - 2] >= rows else {
                throw PipelineError.GenericError.unexpectedOutput("\(name) has shape \(shape); expected rank \(rank) with at least \(rows) rows")
            }
            if let labels {
                let width = rank == 3 ? shape[2] : shape[1]
                guard width == labels else {
                    throw PipelineError.GenericError.unexpectedOutput("\(name) has \(width) labels but the vocabulary has \(labels); the vocabulary files and the model are from different training runs")
                }
            }
           switch array.dataType {
            case .float16, .float32, .double: break
           default: throw PipelineError.GenericError.unexpectedOutput("\(name) has an unsupported element type")
            }
            self.array = array
            self.base = UnsafeRawPointer(array.dataPointer)
            self.dataType = array.dataType
            self.strides = array.strides.map { $0.intValue }
            self.shape = shape
        }

        /// rank 3: value at [0, row, column]
        func value(row: Int, column: Int) -> Float {
            load(strides[1] * row + strides[2] * column)
        }

        /// rank 3: index of the largest value in a row (over the last dimension)
        func argmax(row: Int) -> Int {
            var best = 0
            var bestValue = -Float.infinity
            for k in 0..<shape[2] {
                let v = value(row: row, column: k)
                if v > bestValue { bestValue = v; best = k }
            }
            return best
        }

        /// rank 4 ([1, channels, rows, columns]): value at [0, channel, row, column]
        func value(channel: Int, row: Int, column: Int) -> Float {
            load(strides[1] * channel + strides[2] * row + strides[3] * column)
        }

        private func load(_ offset: Int) -> Float {
            switch dataType {
            case .float32:
                return base.load(fromByteOffset: offset * 4, as: Float.self)
            case .double:
                return Float(base.load(fromByteOffset: offset * 8, as: Double.self))
            default:                                    // .float16, checked in init
                return Self.float(fromHalfBits: base.load(fromByteOffset: offset * 2, as: UInt16.self))
            }
        }

        /// IEEE half -> Float by bit manipulation, so no Float16 type is needed (it isn't
        /// available when building for Intel simulators).
        private static func float(fromHalfBits h: UInt16) -> Float {
            let sign = UInt32(h >> 15) << 31
            let exponent = UInt32((h >> 10) & 0x1F)
            let mantissa = UInt32(h & 0x3FF)
            switch exponent {
            case 0:
                let magnitude = Float(mantissa) / 16_777_216        // subnormal (or zero): mantissa * 2^-24
                return sign == 0 ? magnitude : -magnitude
            case 0x1F:
                return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13))   // infinity / NaN
            default:
                return Float(bitPattern: sign | ((exponent + 112) << 23) | (mantissa << 13))
            }
        }
    }
    
}

protocol BERTpipeEncodedSentence {
    var inputIDs: [Int32]      { get } // length seqLen
    var wordIndex: [Int32] { get }
    var wordCount : Int { get }
    var length: Int { get }
    var pieces: [[String]]? { get } // subtokens
    var validSlots: Int { get }
}

extension BERTpipeEncodedSentence {
    /// MLMultiArrays named like the model's inputs: "input_ids" and "word_index" (Int32).
    func multiArrays() throws -> (inputIDs: MLMultiArray, wordIndex: MLMultiArray) {
        return (try makeArray(inputIDs), try makeArray(wordIndex))
    }
    func makeArray(_ values: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
        let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: values.count)
        for (i, v) in values.enumerated() { pointer[i] = v }
        return array
    }
}

protocol PipelineLoader {
}

extension PipelineLoader{
    // loading
    /// seqLen and maxWords are the second dimension of the two [1, N] inputs.
    static func limits(of model: MLModel) throws -> (seqLen: Int, maxWords: Int) {
        func length(of input: String) throws -> Int {
            guard let shape = model.modelDescription.inputDescriptionsByName[input]?
                .multiArrayConstraint?.shape, shape.count == 2 else {
                throw PipelineError.ConfigurationError.invalidModelInputs("\(input) isn't a [1, N] array input")
            }
            return shape[1].intValue
        }
        let seqLen = try length(of: "input_ids")
        let maxWords = try length(of: "word_index")
        guard maxWords <= seqLen - 1 else {
            throw PipelineError.ConfigurationError.invalidModelInputs(
                "word_index length \(maxWords) must be at most input_ids length \(seqLen) - 1")
        }
        return (seqLen, maxWords)
    }
    
    static func loadLabelVocabularies(languageCode: String,
                                      treebank: String,
                                      bundle: Bundle = .main,
                                      vx: String,
                                      base: BERTlikeBase
    ) throws -> BERTpipeHelperStructs.LabelVocabs {
        
        func vocab(_ label: String, vx: String) throws -> Vocab {
            let name: String
            switch base {
            case .distilbert:
                name = "\(languageCode)_distilbert_\(label)_vocab_\(treebank)\(vx)"
            case .camembert:
                name = "\(languageCode)_camembert_\(label)_vocab_\(treebank)\(vx)"
            case .roberta:
                name = "\(languageCode)_roberta_\(label)_vocab_\(treebank)\(vx)"
            }
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw PipelineError.GenericError.missingResource("\(name).json")
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(VocabData.self, from: data)
            return Vocab(data: decoded)
        }

        return BERTpipeHelperStructs.LabelVocabs(
            upos: try vocab("upos", vx: vx),
            feats: try vocab("feats", vx: vx),
            deprel: try vocab("deprel", vx: vx),
            lemmaRule: try vocab("lemma_rule", vx: vx)
        )
    }
    static func loadMlpackage(named name: String, myConfig: TaggerConfig) throws -> MLModel{
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            throw PipelineError.LoadingError.packageLoadFailed(name)
        }
        do {
            switch myConfig.parsingConfig.modelArchitecture {
            case .distilbert, .camembert:
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                return try MLModel(contentsOf: url, configuration: configuration)
            case .cnnBiLSTM:
                return try MLModel(contentsOf: url)
            }
        } catch {
            throw PipelineError.LoadingError.packageLoadFailed("failed to load model \(name)")
        }
    }
}

// protocol to list specifc attribs all pipelines share : no extensions
protocol PipelineHelper {
//        func runOnSentence(_ sentence: HashableSentence, myConfig: TaggerConfig) throws -> [Token]
    //func runOnSentence(_ sentence: HashableSentence, myConfig: TaggerConfig) -> OnSentResult
    var description: String { get }
    var maxWords: Int { get }
    var taggerModel: MLModel { get }
    var runExplicit: Bool { get }
    var seqLen: Int { get  }
    
}


// protocol specific to bert-likes for subtoken awareness
protocol SubtokenAwarePipelineHelper {
    var seqLen: Int { get }
    
}

protocol LinguisticProcessingHelper{
}

extension LinguisticProcessingHelper{
    // MARK: - Lemma edit-script : functional but not superb lemmatisation
    func applyLemmaRule(form: String, rule: String) -> String {
        var result: String
        if rule == "IDENTITY" {
            result = form.lowercased()
        } else {
            let parts = rule.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let p = Int(parts[0]), let s = Int(parts[1]) else {
                return form
            }
            let middle = String(parts[2])
            let f = Array(form.lowercased())
            if p + s > f.count { return form }
            let prefix = String(f[0..<p])
            let suffix = s > 0 ? String(f[(f.count - s)...]) : ""
            result = prefix + middle + suffix
        }
        if let firstChar = form.first, firstChar.isUppercase {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }
        return result
    }

    // MARK: Dependency parsing
    /// Best tree (Chu-Liu-Edmonds), then the best label for each arc.
    ///
    /// - Parameters:
    ///   - wordCount: number of words; positions are 0 (ROOT) ... wordCount.
    ///   - arcScore: score of `head` as the head of `dependent`.
    ///   - labelScore: score of relation `label` on the arc head -> dependent.
    /// - Returns: one (head, deprel) per word, in word order (ROOT not included).
    func decodeParse(runExplicit: Bool, wordCount: Int,
                     deprelVocab: Vocab,
                     arcScore: (_ dependent: Int, _ head: Int) -> Double,
                     labelScore: (_ label: Int, _ dependent: Int, _ head: Int) -> Double)
        -> [(head: Int, deprel: String)] {
        let n = wordCount + 1
            if runExplicit {
                print("Decoding deps:: raw seq len == \(n)")
            }
            
        // Dense head-score matrix: scoreMatrix[h][d] = score of dependent d attaching to head h.
        // d == 0 (root can't be a dependent) and h == d (a word can't be its own head) are left
        // at -infinity and are never read by the arc-selection loops below.
        // scoreMatrix[head][dependent]; a word can't head itself, and ROOT has no head
        var scoreMatrix = [[Double]](repeating: [Double](repeating: -Double.infinity, count: n), count: n)
        for d in 1..<n {
            for h in 0..<n where h != d {
                scoreMatrix[h][d] = arcScore(d, h)
            }
        }
        let heads = solveArborescence(activeNodes: Array(0..<n), scoreMatrix: scoreMatrix)
        if runExplicit {
            print("heads == \(heads)")
        }

        return (1..<n).map { t in
            // Every non-root node is guaranteed a parent by solveArborescence;
            let head = heads[t] ?? 0 // nil coalesce to be safe
            var bestDeprelId = 0
            var bestDeprelScore = -Double.infinity
            for c in 0..<deprelVocab.itos.count {
                let v = labelScore(c, t, head)
                if v > bestDeprelScore { bestDeprelScore = v; bestDeprelId = c }
            }
            if runExplicit {
                print("Decode deps::\n head ==\(head); deprel===\(deprelVocab.decode(bestDeprelId))")
            }
            return (head: head, deprel: deprelVocab.decode(bestDeprelId))
        }
    }

    // MARK: Chu-Liu-Edmonds maximum spanning arborescence
    /// Solves the maximum-weight spanning arborescence rooted at node 0 over exactly `activeNodes`
    /// (which must include 0), using `scoreMatrix` for edge weights. Returns a map from every
    /// active node except 0 to its chosen parent (also an active node).
    ///
    /// This is a standard recursive implementation of Chu-Liu-Edmonds: greedily pick each node's
    /// best incoming edge; if that produces a cycle, contract the cycle into one representative
    /// node with reweighted edges, recurse on the smaller graph, then expand the result back out.
    /// Recursion terminates because each contraction strictly reduces the number of active nodes,
    /// and a graph with no cycle is returned immediately as-is.
    private func solveArborescence(activeNodes: [Int], scoreMatrix: [[Double]]) -> [Int: Int] {
        // Step 1: each non-root active node's single best incoming edge.
        var bestParent: [Int: Int] = [:]
        for d in activeNodes where d != 0 {
            var best = -Double.infinity
            var bestH = -1
            for h in activeNodes where h != d {
                let s = scoreMatrix[h][d]
                if s > best { best = s; bestH = h }
            }
            bestParent[d] = bestH
        }

        guard let cycle = findCycle(bestParent: bestParent, activeNodes: activeNodes) else {
            // No cycle: the greedy choice is already optimal.
            return bestParent
        }

        // Step 2: contract the cycle into a single representative node (reusing the smallest node id in
        // the cycle, rather than minting a new one, keeps every id a real, meaningful node throughout)
        let cycleSet = Set(cycle)
        let representative = cycle.min()!

        // Total weight of the cycle's own internal edges -- used below to work out true cost of "breaking"
        // the cycle at whichever node ends up accepting an external edge instead.
        var cycleWeight = 0.0
        for v in cycle {
            cycleWeight += scoreMatrix[bestParent[v]!][v]
        }

        let newActiveNodes = activeNodes.filter { !cycleSet.contains($0) || $0 == representative }
        var newScoreMatrix = scoreMatrix

        // Bookkeeping so the contracted-graph result can be expanded back into real node ids afterward
        var enterFrom: [Int: Int] = [:] // u -> which cycle node the (u -> representative) edge really targets
        var exitTo: [Int: Int] = [:]    // w -> which cycle node the (representative -> w) edge really originates from

        for u in activeNodes where !cycleSet.contains(u) {
            var bestIn = -Double.infinity
            var bestVIn = -1
            var bestOut = -Double.infinity
            var bestVOut = -1
            for v in cycle {
                // Incoming: cost of accepting edge (u -> v) instead of v's  current in-cycle edge, while
                // keeping every other cycle edge intact.
                let reweighted = scoreMatrix[u][v] - scoreMatrix[bestParent[v]!][v] + cycleWeight
                if reweighted > bestIn { bestIn = reweighted; bestVIn = v }

                // Outgoing: plain best edge leaving the cycle to u -- no reweighting needed, since
                // which internal edge eventually gets broken doesn't affect edges leaving the cycle.
                let s = scoreMatrix[v][u]
                if s > bestOut { bestOut = s; bestVOut = v }
            }
            newScoreMatrix[u][representative] = bestIn
            enterFrom[u] = bestVIn
            newScoreMatrix[representative][u] = bestOut
            exitTo[u] = bestVOut
        }

        // Step 3: recurse on the smaller, contracted graph.
        let contractedParents = solveArborescence(activeNodes: newActiveNodes, scoreMatrix: newScoreMatrix)

        // Step 4: expand back. Every cycle node keeps its original in-cycle parent, except the one node
        // where an external edge broke the cycle -- that node's real parent is whichever external node
        // fed into the cycle at that point.
        var result = contractedParents
        result.removeValue(forKey: representative)
        for v in cycle {
            result[v] = bestParent[v]
        }
        if let repParent = contractedParents[representative], let breakNode = enterFrom[repParent] {
            result[breakNode] = repParent
        }

        // Any outside node whose contracted parent came out as the representative actually attaches to
        // whichever real cycle node achieved that best exit edge.
        for (node, parent) in contractedParents where parent == representative {
            if let realParent = exitTo[node] {
                result[node] = realParent
            }
        }
        return result
    }

    private func findCycle(bestParent: [Int: Int], activeNodes: [Int]) -> [Int]? {
        var visitedGlobally = Set<Int>()

        for start in activeNodes where start != 0 && !visitedGlobally.contains(start) {
            var path: [Int] = []
            var pathSet = Set<Int>()
            var current = start

            while true {
                if pathSet.contains(current) {
                    let cycleStartIndex = path.firstIndex(of: current)!
                    return Array(path[cycleStartIndex...])
                }
                if visitedGlobally.contains(current) || current == 0 {
                    break // reached root, or a previously-confirmed cycle-free path -- no cycle here
                }
                path.append(current)
                pathSet.insert(current)
                visitedGlobally.insert(current)
                current = bestParent[current]!
            }
        }
        return nil
    }
    
    // formatting output
    // MARK: - Output formatting
    func formatRaw(_ lines: [ConllLineContent]) -> [String] {
        lines.map { line in
            switch line {
            case .row(let tok): return tok.conllRaw
            case .blank: return ""
            }
        }
    }

    /// Use string count to column-align rows of each sent  independently
     func formatTidy(_ lines: [ConllLineContent]) -> [String] {
        var result: [String] = []
        var currentRows: [[String]] = []

        func flushSentence() {
            guard let columnCount = currentRows.first?.count else { return }
            var widths = Array(repeating: 0, count: columnCount)
            for row in currentRows {
                for (i, field) in row.enumerated() {
                    widths[i] = max(widths[i], field.count)
                }
            }
            for row in currentRows {
                let padded = row.enumerated().map { i, field in
                    field.padding(toLength: widths[i], withPad: " ", startingAt: 0)
                }
                result.append(padded.joined(separator: "  "))
            }
            currentRows = []
        }

        for line in lines {
            switch line {
            case .row(let tok):
                currentRows.append([
                    String(tok.tokid), tok.form, tok.lemma, tok.upos,
                    tok.xpos, tok.feats, tok.head, tok.deprel,
                ])
            case .blank:
                flushSentence()
                result.append("")
            }
        }
        flushSentence() // in case the input didn't end with a trailing .blank
        return result
    }
}

protocol BERTderivedPipelineHelper: LinguisticProcessingHelper, PipelineHelper {
    // things conforming to this protocol will have these
    var labels: BERTpipeHelperStructs.LabelVocabs { get }
    var tokenizer: BERTlikeTokenizerHelper { get }
}
    

// extension defining functs used after pipeline loaded
extension BERTderivedPipelineHelper  {
// make this stuff available for all conforming
        func tokenize(_ naughtyString: String) -> HashableSentence{
        let input = naughtyString
        
        let intermediate = input.split(separator: " ")
        let output = intermediate.map {String($0)}
        let outputSent = HashableSentence(id: "e2", tokens: output, conllMetas: [])
        print("this should't have been callable…")
        return outputSent
    }
    
    func runOnSentence(_ sentence: HashableSentence, myConfig: TaggerConfig) throws -> OnSentResult {
        if runExplicit { print("running on sents with bert pipeline") }
        
        guard !sentence.tokens.isEmpty else {
            return OnSentResult(sentence: sentence, resultType: .empty, decoded: [])
        }
        // maxWords counts the ROOT slot, so the most real words allowed is maxWords - 1
        guard sentence.tokens.count < maxWords else {
            return OnSentResult(sentence: sentence, resultType: .tooManyWords, decoded: [])
        }
        var thisTokenizer: BERTlikeTokenizerHelper
        var currentPieceCount: Int = -3
        
        switch myConfig.parsingConfig.modelArchitecture{
        case .camembert:
            if let useThis = tokenizer as? SentencePieceTokenizer {
                thisTokenizer = useThis
                thisTokenizer.showPieces = myConfig.exportConfig.getsubtokens
        } else {
            throw PipelineError.GenericError.unexpectedOutput("tok distilbert")
        }
        case .distilbert:
            if let useThis = tokenizer as? WordPieceTokenizer {
                thisTokenizer = useThis
                thisTokenizer.showPieces = myConfig.exportConfig.getsubtokens
            } else {
                throw PipelineError.GenericError.unexpectedOutput("tok distilbert")
            }
            
        default:
            throw PipelineError.ConfigurationError.architectureConflict
        }
        
        do {
            guard let encoded = try? thisTokenizer.encode(words: sentence.tokens, seqLen: seqLen, maxWords: maxWords
            ) else {
                return OnSentResult(sentence: sentence, resultType: .otherError, decoded: [])
            }
            switch myConfig.parsingConfig.modelArchitecture{
            case .camembert:
                currentPieceCount = encoded.validSlots
            case .distilbert:
                currentPieceCount = encoded.pieces?.count ?? -4
            default:
                throw PipelineError.ConfigurationError.architectureConflict
                
            }
            let output = try predict(encoded) //
            let decoded = try decode(output, words: sentence.tokens, pieces: encoded.pieces) // same as decode in WP methods ?
            return OnSentResult(sentence: sentence,  subtokCount: currentPieceCount, resultType: .success, decoded: decoded)
        } catch PipelineError.TokPieceError.tooManySubwords {
            return OnSentResult(sentence: sentence,  subtokCount: currentPieceCount, resultType: .tooManySubtoks, decoded: [])
        } catch PipelineError.TokPieceError.tooManyWords {                              // backstop; the guard above catches this first
            return OnSentResult(sentence: sentence, resultType: .tooManyWords, decoded: [])
        } catch {
            if runExplicit { print("sentence failed: \(error.localizedDescription)") }
            return OnSentResult(sentence: sentence, resultType: .otherError, decoded: [])
        }
    }
    
    func predict(_ encoded: BERTpipeEncodedSentence) throws -> MLFeatureProvider {
            let arrays = try encoded.multiArrays()
            let inputs = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: arrays.inputIDs),
                "word_index": MLFeatureValue(multiArray: arrays.wordIndex),
            ])
            do {
                return try taggerModel.prediction(from: inputs)
            } catch {
                throw PipelineError.ProcessingError.predictionFailed(error)
            }
        }
    
    func decode(_ output: MLFeatureProvider, words: [String],
                             pieces: [[String]]?) throws -> [Token] {
        /// 6 padded output tensors -> labelled tokens. Only the first (words + 1) cols mean anything, rest is PAD
        let n = words.count + 1
        let upos = try BERTpipeHelperStructs.LogitReader(output, "upos_logits", rank: 3, rows: n, labels: labels.upos.itos.count)
        let feats = try BERTpipeHelperStructs.LogitReader(output, "feats_logits", rank: 3, rows: n, labels: labels.feats.itos.count)
        let lemmaRules = try BERTpipeHelperStructs.LogitReader(output, "lemma_rule_logits", rank: 3, rows: n,
                                                               labels: labels.lemmaRule.itos.count)
        let arc = try BERTpipeHelperStructs.LogitReader(output, "arc_logits", rank: 3, rows: n)
        let deprels = try BERTpipeHelperStructs.LogitReader(output, "label_logits", rank: 4, rows: n,
                                                            labels: labels.deprel.itos.count)
        
        // deprel, head decoding
        let parse = decodeParse(
            runExplicit: true,
            wordCount: words.count,
            deprelVocab: labels.deprel,
            arcScore: { dependent, head in Double(arc.value(row: dependent, column: head)) },
            labelScore: { label, dependent, head in
                Double(deprels.value(channel: label, row: dependent, column: head))
            }
        )
        
        guard parse.count == words.count else {
            throw PipelineError.GenericError.unexpectedOutput(
                "parse decoder returned \(parse.count) (head, deprel) pairs for \(words.count) words")
        }
        var tokens: [Token] = []
        tokens.reserveCapacity(words.count)
        for i in 1..<n {
            let form = words[i - 1]
            let rule = labels.lemmaRule.decode(lemmaRules.argmax(row: i))
            tokens.append(Token(
                tokid: i,
                form: "\(form)_zz",
                lemma: applyLemmaRule(form: form, rule: rule),
                upos: labels.upos.decode(upos.argmax(row: i)),
                xpos: "_",
                feats: labels.feats.decode(feats.argmax(row: i)),
                head: String(parse[i - 1].head),
                deprel: parse[i - 1].deprel,
                col8: "_zz_",
                col9: "_",
                subTokens: pieces?[i - 1]
            ))
            if runExplicit{
                var subels: String = "empty"
                let tidy1 = pieces?[i-1]
                if let success = tidy1{
                    subels = success.joined(separator: "/")
                }
                print("\(form) :: \(subels)")
            }
        }
        return tokens
    }
        
    
    
}

// combination of extension: Language and a protocol
// 1. Define a protocol that guarantees availableTBs exists
protocol TreebankProvidable {
    associatedtype TreebankType: Hashable
    var availableTBs: [TreebankType] { get }
    var defaultTB: TreebankType { get } //
}

// 2. Conforming  language enum to it
extension Language: TreebankProvidable {
    typealias TreebankType = Language.Treebank
}

//MARK: 2 : services for pipelines : static functs on Structs used with results
enum PipelineServices {
    struct ResultStorageManager {
        @discardableResult
        static func getRunsDirectory() throws -> URL? {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let runsURL = documents.appendingPathComponent("runs", isDirectory: true)
            
            do {  // Automatically creates the folder if it's missing
                try FileManager.default.createDirectory(at: runsURL, withIntermediateDirectories: true, attributes: nil)
                return runsURL
            } catch {
                print("Failed to create 'runs' directory: \(error)")
                throw PipelineError.ExportError.outputFolderCreationError
            }
        }
        // save run data in sandbox
        static func saveRun(_ runOutput: RunOutput) throws ->URL? {
            guard let runsFolder = try getRunsDirectory() else { throw PipelineError.ExportError.outputFolderCreationError }
            let fileURL = runsFolder.appendingPathComponent("\(runOutput.id).json")
            
            do {
                let data = try JSONEncoder().encode(runOutput)
                try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
                print("Successfully saved to: \(fileURL.path)")
                return fileURL
            } catch {
                print("Failed to save result: \(error)")
                throw PipelineError.ExportError.fileSaveError(filename: fileURL.absoluteString)
            }
        }
        
        static func loadRun(runID: String) throws -> RunOutput? {
            guard let runsFolder = try getRunsDirectory() else { throw PipelineError.ExportError.outputFolderCreationError }
            let fileURL = runsFolder.appendingPathComponent("\(runID).json")
            
            do {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder().decode(RunOutput.self, from: data)
            } catch {
                print("Failed to load result: \(error)")
                return nil
            }
        }
    }
    struct ExporterService {
         // 1. A reusable helper function to resolve the bookmark from standard UserDefaults
        static func resolveDefaultBookmark() -> URL {
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: "outputDirBookmark") {
                var isStale = false
                if let resolved = try? URL(resolvingBookmarkData: data,
                                         options: .withoutUI,
                                         relativeTo: nil,
                                         bookmarkDataIsStale: &isStale) {
                    return resolved
                }
            }
            // Fallback default if bookmark is missing or fails to resolve
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }
        
        /// Writes processing output string directly to a user-selected folder URL
        static func exportDataToFile(
            exportContent: String,
            customName: String,
            targetFolderURL: URL,
            exportFormat: ExportFormat,
            runExplicit: Bool
            
        ) throws -> URL {
            //1 check file extension
            let fileExtension = exportFormat.fileExtension

            if runExplicit{
                print("step1 success : file extension exists")
            }

            // 2. Format sanitized filename
            var safeName = customName.sanitizedFileName
            if !safeName.hasSuffix(".\(fileExtension)") {
                safeName += ".\(fileExtension)"
            }
            if runExplicit{
                print(safeName)
                print("step2 success")
            }

            // 3. Resolve directory & obtain security scope
            print("start step 3 : resolve dir + scope")
            let (folder, _) = try resolveOutputDir(targetFolderURL: targetFolderURL)

            // 4a. Elevate security permissions BEFORE constructing child paths
            let gotAccess = folder.startAccessingSecurityScopedResource()
            if runExplicit {
                print("step4a gotAccess == \(gotAccess), scheme == \(folder.scheme ?? "nil")")
            }
            defer {
                if gotAccess {
                    folder.stopAccessingSecurityScopedResource()
                }
            }
            // 4b. Construct destination path inside the accessed directory
            let destinationFileURL = folder.appendingPathComponent(safeName)
            if runExplicit && destinationFileURL.isFileURL {
                print("step4b success:: -> \(destinationFileURL)")
            } else {
                print("destination file URL failed isURL test")
            }
            print("line 418")
            // 5. Write
            do {
                try exportContent.write(to: destinationFileURL, atomically: true, encoding: .utf8)
                if runExplicit{
                    print("step5 success URL == \(destinationFileURL.path())")
                }
            } catch {
                let e = error as NSError
                print("write failed: \(e.domain) \(e.code) \(e.localizedDescription)")
                throw error

            }
            return destinationFileURL
        }
                static func resolveOutputDir(targetFolderURL: URL) throws -> (url: URL, isSecurityScoped: Bool) {
            let defaults = UserDefaults.standard

            if let data = defaults.data(forKey: StoreKey.outputBookmark) {
                var isStale = false
                do {
                    // Resolve using security scope options
                    let resolvedURL = try URL(
                        resolvingBookmarkData: data,
                        options: .withoutUI,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    
                    // If bookmark is stale, refresh and update stored data
                    if isStale {
                        if resolvedURL.startAccessingSecurityScopedResource() {
                            defer { resolvedURL.stopAccessingSecurityScopedResource() }
                            if let freshData = try? resolvedURL.bookmarkData(
                                options: .minimalBookmark,
                                includingResourceValuesForKeys: nil,
                                relativeTo: nil
                            ) {
                                defaults.set(freshData, forKey: StoreKey.outputBookmark)
                            }
                        }
                    }
                    
                    return (resolvedURL, true)
                } catch {
                    print("Failed to resolve bookmark: \(error)")
                }
            }
            
            // Fallback: URL chosen in current session or internal sandbox
            let fallback = targetFolderURL.isFileURL
                ? targetFolderURL
                : URL(fileURLWithPath: targetFolderURL.path, isDirectory: true)
                
            return (fallback, false)
        }
    }
}


protocol BERTlikeTokenizerHelper{
    var showPieces: Bool  { get set }
    func encode(words: [String], seqLen: Int, maxWords: Int) throws -> BERTpipeEncodedSentence?
}


/// Implemented by the existing WordPiece tokenizer (via a small adapter) and by
/// SentencePieceTokenizer, so the export/prediction code doesn't care which one it has.
protocol SubwordEncoder {
    func encode(words: [String], seqLen: Int, maxWords: Int) throws -> BERTpipeEncodedSentence?
}
