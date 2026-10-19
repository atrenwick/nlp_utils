//
//  BERTbasedPipeline.swift
//  Tagger
//
//  Created by Adam on 18/10/2026.
//

import Foundation
import CoreML
import SwiftUI


final class UDPipelineBERTbased{
    var wordPieceTokenizer: WordPieceTokenizer
    private let taggerModel: MLModel
    private let labels: LabelVocabularies

    /// fixed lengths the model was converted with, loaded from model for safety
    let seqLen: Int
    let maxWords: Int
    let runExplicit = true
    /// Designated init: takes already-loaded pieces, which also makes it easy to test.
    init(taggerModel: MLModel, wordPieceTokenizer: WordPieceTokenizer, labels: LabelVocabularies, languageCode: String, treebank: String) throws {
        let limits = try UDPipelineBERTbased.limits(of: taggerModel)
        self.taggerModel = taggerModel
        self.wordPieceTokenizer = wordPieceTokenizer
        self.labels = labels
        self.seqLen = limits.seqLen
        self.maxWords = limits.maxWords
    }

    /// Loads everything for one language/treebank. Building the tokenizer reads a ~100k-entry
    /// vocabulary, so call this off the main thread (for example inside Task.detached).
    convenience init(languageCode: String, treebank: String) throws {
        let model = try UDPipelineBERTbased.loadModel(named: "\(languageCode)_distilbert_tagger_parser_\(treebank)")
        var wordPieceTokenizer = try WordPieceTokenizer.fromBundle(languageCode: languageCode,
                                                          treebank: treebank)
        let labels = try LabelVocabularies.loadLabelVocabularies(languageCode: languageCode, treebank: treebank)
        try self.init(taggerModel: model, wordPieceTokenizer: wordPieceTokenizer, labels: labels, languageCode:  languageCode, treebank: treebank)
    }

    static func load(languageCode: String, treebank: String) async throws -> UDPipelineBERTbased {
        /// this static func was in its own extension tot he class
        try await Task.detached(priority: .userInitiated) {
            try await UDPipelineBERTbased(languageCode: languageCode, treebank: treebank)
        }.value
    }

    private static func loadModel(named name: String) throws -> MLModel {
        // Xcode compiles a bundled .mlpackage into a .mlmodelc at build
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            throw UDPipelineError.modelLoadFailed(name)
        }
        let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            do {
                return try MLModel(contentsOf: url, configuration: configuration)
            } catch {
                throw UDPipelineError.modelLoadFailed("load failed")
            }
        }
    /// seqLen and maxWords are the second dimension of the two [1, N] inputs.
    private static func limits(of model: MLModel) throws -> (seqLen: Int, maxWords: Int) {
        func length(of input: String) throws -> Int {
            guard let shape = model.modelDescription.inputDescriptionsByName[input]?
                    .multiArrayConstraint?.shape, shape.count == 2 else {
                throw UDPipelineError.invalidModelInputs("\(input) isn't a [1, N] array input")
            }
            return shape[1].intValue
        }
        let seqLen = try length(of: "input_ids")
        let maxWords = try length(of: "word_index")
        guard maxWords <= seqLen - 1 else {
            throw UDPipelineError.invalidModelInputs(
                "word_index length \(maxWords) must be at most input_ids length \(seqLen) - 1")
        }
        return (seqLen, maxWords)
    }
    func annotate(words: [String], showWordPieces: Bool = true) throws -> Sentence {
        /// Annotates one sentence. Runs the model synchronously (tens of milliseconds), so call it
        /// from a background task, not from the main thread.
        ///
        /// Throws PipelineError.emptyInput, WordPieceError.tooManyWords / .tooManySubwords when the
        /// sentence doesn't fit the model's fixed size, or a PipelineError for model problems.
        // this method was in an extension1 to UDPipelineBERTBased - annotating+decoding
        guard !words.isEmpty else { throw ParseProcessingError.emptyInput }
        
        var wordPieceTokenizer = self.wordPieceTokenizer                  // a copy; the vocabulary isn't duplicated
        //        wordPieceTokenizer.showWordPieces = showWordPieces // default set to true for the moment
        
        let encoded = try wordPieceTokenizer.encode(words: words, seqLen: seqLen, maxWords: maxWords)
        
        let output = try predict(encoded)
        return try decode(output, words: words, wordPieces: encoded.wordPieces)
    }
    func annotate(sentences: [[String]],
                  showWordPieces: Bool = false,
                  progress: ((Int, Int) -> Void)? = nil) async throws -> [Result<Sentence, Error>] {
        /// Annotates many sentences. A sentence that fails (too long, say) becomes a .failure
        /// entry instead of stopping the whole run. Results are in the same order as the input.
        /// Honours task cancellation. `progress` is called as (done, total) on the calling task.
        // this method was in an extension1 to UDPipelineBERTBased - annotating+decoding
        var results: [Result<Sentence, Error>] = []
        results.reserveCapacity(sentences.count)
        for (index, words) in sentences.enumerated() {
            try Task.checkCancellation()
            results.append(Result { try annotate(words: words, showWordPieces: showWordPieces) })
            progress?(index + 1, sentences.count)
        }
        return results
    }
    
    // MARK: Running the model
    private func predict(_ encoded: WordPieceEncodedSentence) throws -> MLFeatureProvider {
        // this method was in an extension1 to UDPipelineBERTBased - annotating+decoding
        let arrays = try encoded.multiArrays()
        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: arrays.inputIDs),
            "word_index": MLFeatureValue(multiArray: arrays.wordIndex),
        ])
        do {
            return try taggerModel.prediction(from: inputs)
        } catch {
            throw ParseProcessingError.predictionFailed(error)
        }
    }

    // MARK: Decoding
    private func decode(_ output: MLFeatureProvider, words: [String],
                        wordPieces: [[String]]?) throws -> Sentence {
        /// Turns the six padded output tensors into labelled tokens. Only the first words + 1
        /// rows/columns mean anything (row 0 is the ROOT slot); the rest is padding.
        // this method was in an extension1 to UDPipelineBERTBased - annotating+decoding
        let n = words.count + 1
        
        let upos = try LogitReader(output, "upos_logits", rank: 3, rows: n)
        let xpos = try LogitReader(output, "xpos_logits", rank: 3, rows: n)
        let feats = try LogitReader(output, "feats_logits", rank: 3, rows: n)
        let lemmaRules = try LogitReader(output, "lemma_rule_logits", rank: 3, rows: n)
        let arc = try LogitReader(output, "arc_logits", rank: 3, rows: n)
        let deprels = try LogitReader(output, "label_logits", rank: 4, rows: n)
        
        struct WrapperForDepDecoding{
            let arcLogits: LogitReader
            let deprelLogits: LogitReader
        }
        // arcScores[dependent][head], ROOT included. A word can't head itself.
        var arcScores = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        for dependent in 0..<n {
            for head in 0..<n {
                arcScores[dependent][head] = dependent == head
                ? -1e9 : arc.value(row: dependent, column: head)
            }
        }
//        let heads = decodeHeads(arcScores: arcScores)           // length n; entry 0 unused
        let raw = WrapperForDepDecoding(
            arcLogits: arc,
            deprelLogits: deprels
        )
        let depsDecoded = decodeDependenciesFromWrapper(raw)
        let headsDecoded = depsDecoded.map { String($0.head) }
        let deprelsDecoded = depsDecoded.map { $0.deprel }

        
        guard headsDecoded.count == n else {
            throw ParseProcessingError.unexpectedOutput("head decoder returned \(headsDecoded.count) heads for \(n) positions")
        }
        
        var tokens: [Token] = []
        tokens.reserveCapacity(words.count)
        for i in 1..<n {
            let form = words[i - 1]
            let rule = Self.label(labels.lemmaRule, lemmaRules.argmax(row: i))
            tokens.append(Token(
                tokid: i,
                form: form,
                lemma: applyLemmaRule(form: form, rule: rule),
                upos: Self.label(labels.upos, upos.argmax(row: i)),
                xpos: "_",
                feats: Self.label(labels.feats, feats.argmax(row: i)),
                head: headsDecoded[i],
                deprel: Self.label(labels.deprel, deprelsDecoded.argmaxChannel(row: i, column: headsDecoded[i])),
                col8: "_",
                col9: "_",
                subTokens: wordPieces?[i - 1]
            ))
        }
        return Sentence(
            sentID: "sentIDstring",
            conllData: tokens,
            conllMetas: [])
    }
    
    /// id -> label string. One line to adapt to your Vocab class.
    // this method was in an extension1 to UDPipelineBERTBased - annotating+decoding
    private static func label(_ vocab: Vocab, _ id: Int) -> String {
        vocab.decode(id)                                        // <- your Vocab's id -> string call
    }
    //////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
    //COPY OF DEPENDENCY DECODE FROM CNN-BILSTM pipeline
    private struct TaggerRawOutput {
        let sentence: HashableSentence
        let seqLen: Int
        let uposLogits: MLMultiArray
        let xposLogits: MLMultiArray
        let featsLogits: MLMultiArray
        let ruleLemmaLogits: MLMultiArray //rulebase lemma logits
        let decodedLemmas: [String]
        let arcLogits: MLMultiArray
        let labelLogits: MLMultiArray
    }
    
    // MARK: Step 5 (decode) -- dependency parsing
    /// One (head, deprel) pair per real word, decoded via Chu-Liu-Edmonds (max spanning arborescence,
    /// rooted at node 0), which guarantees a valid, cycle-free dependency tree with a single root --
    /// unlike a per-word greedy parserArgmax, which can produce cycles or multiple roots.
    private func decodeDependencies(_ raw: TaggerRawOutput) -> [(head: Int, deprel: String)] {
        let n = raw.seqLen
        if runExplicit {
            print("Decoding deps:: raw seq len == \(n)")
        }
        // Dense head-score matrix: scoreMatrix[h][d] = score of dependent d attaching to head h.
        // d == 0 (root can't be a dependent) and h == d (a word can't be its own head) are left
        // at -infinity and are never read by the arc-selection loops below.
        var scoreMatrix = [[Double]](repeating: [Double](repeating: -Double.infinity, count: n), count: n)
        for d in 1..<n {
            for h in 0..<n where h != d {
                scoreMatrix[h][d] = raw.arcLogits[[0, d, h] as [NSNumber]].doubleValue
            }
        }
        //print("scoreMatrix == \(scoreMatrix)")
        let heads = solveArborescence(activeNodes: Array(0..<n), scoreMatrix: scoreMatrix)
        if runExplicit {
            print("heads == \(heads)")
        }
        return (1..<n).map { t in
            // Every non-root node is guaranteed a parent by solveArborescence;
            let head = heads[t] ?? 0 // nil colalesce to be safe
            
            var bestDeprelId = 0
            var bestDeprelScore = -Double.infinity
            for c in 0..<labels.deprel.itos.count {
                let v = raw.labelLogits[[0, c, t, head] as [NSNumber]].doubleValue
                if v > bestDeprelScore { bestDeprelScore = v; bestDeprelId = c }
            }
            if runExplicit {
                print("Decode deps::\n head ==\(head); deprel===\(labels.deprel.decode(bestDeprelId))")
            }
            return (head: head, deprel: labels.deprel.decode(bestDeprelId))
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

    ///
    // COPY OF Apply lemma rule from CNN-BiLSTM pipeline
    // MARK: - Lemma edit-script : functional but not superb lemmatisation
    private func applyLemmaRule(form: String, rule: String) -> String {
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
    // END COPY OF CNN-BiLSTM lemma scripr
    //////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
}

    






// MARK: - Label vocabularies

/// The five vocabularies that turn output indices back into labels. They must come from
/// the same training run as the model (train_bert.py writes them next to it); the old
/// BiLSTM vocabularies number the labels differently.
struct LabelVocabularies {
    let upos: Vocab
    let feats: Vocab
    let deprel: Vocab
    let lemmaRule: Vocab
    
    static func loadLabelVocabularies(languageCode: String,
                                      treebank: String,
                                      bundle: Bundle = .main
    ) throws -> LabelVocabularies {
        
        func vocab(_ label: String) throws -> Vocab {
            let name = "\(languageCode)_bert_\(label)_vocab_\(treebank)"
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw UDPipelineError.missingResource("\(name).json")
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(VocabData.self, from: data)
            return Vocab(data: decoded)
        }

        return LabelVocabularies(
            upos: try vocab("upos"),
            feats: try vocab("feats"),
            deprel: try vocab("deprel"),
            lemmaRule: try vocab("lemma_rule")
        )
    }
}


//// MARK: - Annotate
//extension UDPipelineBERTbased {
//}
    
// MARK: - Reading Core ML output arrays

/// Reads values out of an MLMultiArray without boxing every element. Honours the array's
/// strides (Core ML may pad rows) and its element type (the model's outputs are normally
/// float16; float32 and double are handled too).
// this struct was and should remain its own private struct

private struct LogitReader {
    private let array: MLMultiArray             // keeps the buffer alive
    private let base: UnsafeRawPointer
    private let dataType: MLMultiArrayDataType
    private let strides: [Int]
    private let shape: [Int]

    /// - Parameters:
    ///   - rank: expected number of dimensions (3 = [1, rows, width], 4 = [1, channels, rows, columns])
    ///   - rows: how many rows the caller will read (words + 1)
    init(_ output: MLFeatureProvider, _ name: String, rank: Int, rows: Int) throws {
        guard let array = output.featureValue(for: name)?.multiArrayValue else {
            throw ParseProcessingError.unexpectedOutput("\(name) is missing")
        }
        let shape = array.shape.map { $0.intValue }
        guard shape.count == rank, shape[rank - 2] >= rows else {
            throw ParseProcessingError.unexpectedOutput("\(name) has shape \(shape); expected rank \(rank) with at least \(rows) rows")
        }
        switch array.dataType {
        case .float16, .float32, .double: break
        default: throw ParseProcessingError.unexpectedOutput("\(name) has an unsupported element type")
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

    /// rank 4 ([1, channels, rows, columns]): the channel with the largest value at [row, column]
    func argmaxChannel(row: Int, column: Int) -> Int {
        var best = 0
        var bestValue = -Float.infinity
        for c in 0..<shape[1] {
            let v = load(strides[1] * c + strides[2] * row + strides[3] * column)
            if v > bestValue { bestValue = v; best = c }
        }
        return best
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
