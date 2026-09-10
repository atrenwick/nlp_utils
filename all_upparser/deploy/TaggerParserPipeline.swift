
import CoreML
import Foundation


// MARK: - Vocabulary
//structure to decode the vocab data JSON file
private struct VocabData: Decodable {
    let itos: [String]
    let pad: String
    let unk: String
}
//define the vocab class
final class Vocab {
    let itos: [String]
    let stoi: [String: Int]
    let pad: String
    let unk: String
    
    //   //init method for the vocab class
    fileprivate init(data: VocabData) {
        itos = data.itos
        pad = data.pad
        unk = data.unk
        var map = [String: Int](minimumCapacity: data.itos.count)
        for (i, s) in data.itos.enumerated() { map[s] = i }
        stoi = map
    }

    var unkId: Int { stoi[unk] ?? 1 }

    func encode(_ token: String) -> Int {
        stoi[token] ?? unkId
    }

    func decode(_ id: Int) -> String {
        (id >= 0 && id < itos.count) ? itos[id] : unk
    }

    //func to get path to file, load, decode and return decoded data based on name of json file
    static func load(named name: String, bundle: Bundle = .main) throws -> Vocab {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw UDPipelineError.missingResource("\(name).json")
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(VocabData.self, from: data)
        return Vocab(data: decoded)
    }
}



// MARK: - Errors

enum UDPipelineError: Error, LocalizedError {
    case missingResource(String)
    case modelLoadFailed(String)
    case lemmatizationFailed(String)
    case predictionFailed(String)
    case invalidLevel(Int)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "Missing bundled resource: \(name). Did you add it to the app target?"
        case .modelLoadFailed(let name):
            return "Failed to load Core ML model '\(name)'. Did you add \(name).mlpackage to the app target?"
        case .lemmatizationFailed(let msg):
            return "Lemmatization failed: \(msg)"
        case .predictionFailed(let msg):
            return "Prediction failed: \(msg)"
        case .invalidLevel(let level):
            return "Invalid pipeline level \(level): must be between 1 and 5."
        }
    }
}


// MARK: - Pipeline

final class UDPipeline {
    static let rootToken = "<root>"
    static let maxWordLen = 20 // matches tagger_parser/data.py's encode_sentence default
    
    private let tokenizerModel: MLModel
    private let taggerModel: MLModel
    private let lemmatizerRunner: LemmatizerRunner
    
    private let tokenizerCharVocab: Vocab
    private let wordVocab: Vocab
    private let taggerCharVocab: Vocab
    private let uposVocab: Vocab
    //private let xposVocab: Vocab
    private let featsVocab: Vocab
    private let deprelVocab: Vocab
//    private let lemmaRuleVocab: Vocab

    init(languageCode: String, treebank: String) throws {
        tokenizerModel = try Self.loadModel(named: "\(languageCode)_tokenizer_\(treebank)")
        taggerModel = try Self.loadModel(named: "\(languageCode)_tagger_parser_\(treebank)")

        tokenizerCharVocab = try Vocab.load(named: "\(languageCode)_tokenizer_char_vocab_\(treebank)")
        wordVocab = try Vocab.load(named: "\(languageCode)_word_vocab_\(treebank)")
        taggerCharVocab = try Vocab.load(named: "\(languageCode)_tagger_char_vocab_\(treebank)")
        uposVocab = try Vocab.load(named: "\(languageCode)_upos_vocab_\(treebank)")
        //xposVocab = try Vocab.load(named: "\(languageCode)_xpos_vocab\(treebank)")
        featsVocab = try Vocab.load(named: "\(languageCode)_feats_vocab_\(treebank)")
        deprelVocab = try Vocab.load(named: "\(languageCode)_deprel_vocab_\(treebank)")
//        lemmaRuleVocab = try Vocab.load(named: "\(languageCode)_lemma_rule_vocab\(treebank)")
        self.lemmatizerRunner = try LemmatizerRunner(languageCode: languageCode)
    }
    

    private static func loadModel(named name: String) throws -> MLModel {
        // Xcode compiles a bundled .mlpackage into a .mlmodelc at build
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            throw UDPipelineError.modelLoadFailed(name)
        }
        return try MLModel(contentsOf: url)
    }

    // MARK: Step 1 -- character-level tokenizer / sentence segmenter

    /// Runs raw text through the tokenizer model and returns one
    /// `TokenisedSentence` per detected sentence, numbered from "1".
    func tokenize(_ text: String) throws -> [TokenisedSentence] {
        let chars = Array(text)
        guard !chars.isEmpty else { return [] }

        let ids = chars.map { Int32(tokenizerCharVocab.encode(String($0))) }
        let inputArray = try makeIntArray(ids, shape: [1, NSNumber(value: ids.count)])
        let provider = try MLDictionaryFeatureProvider(
            dictionary: ["char_ids": MLFeatureValue(multiArray: inputArray)]
        )
        let output = try tokenizerModel.prediction(from: provider)
        guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
            throw UDPipelineError.predictionFailed("tokenizer produced no 'logits' output")
        }

        var tokenLists: [[String]] = []
        var currentSentence: [String] = []
        var currentWord = ""

        for (i, ch) in chars.enumerated() {
            let label = argmax(logits, prefix: [0, i], dimSize: 4)
            switch label {
            case 0: // inside token
                currentWord.append(ch)
            case 1: // token end, sentence continues
                currentWord.append(ch)
                currentSentence.append(currentWord)
                currentWord = ""
            case 2: // token end, sentence ends
                currentWord.append(ch)
                currentSentence.append(currentWord)
                currentWord = ""
                tokenLists.append(currentSentence)
                currentSentence = []
            default: // space / non-token character
                break
            }
        }
        if !currentWord.isEmpty { currentSentence.append(currentWord) }
        if !currentSentence.isEmpty { tokenLists.append(currentSentence) }

        return tokenLists.enumerated().map { i, tokens in
            TokenisedSentence(id: String(i + 1), tokens: tokens)
        }
    }

    // MARK: Step 2 -- run the tagger-parser

    /// Holds the raw tensors from 1 tagger_parser model call for 1 sent
    ///`seqLen` includes the synthetic ROOT index 0, so real words are indices 1,2....<seqLen.
    private struct TaggerRawOutput {
        let sentence: TokenisedSentence
        let seqLen: Int
        let uposLogits: MLMultiArray
        let xposLogits: MLMultiArray
        let featsLogits: MLMultiArray
//        let lemmaLogits: MLMultiArray
        let decodedLemmas: [String]
        let arcLogits: MLMultiArray
        let labelLogits: MLMultiArray
    }

    private func runTaggerParserModel(on sentence: TokenisedSentence) throws -> TaggerRawOutput {
        let tokens = sentence.tokens
        let seqLen = tokens.count + 1 // +1 for the synthetic ROOT at index 0

        var wordIds: [Int32] = [Int32(wordVocab.encode(Self.rootToken))]
        var charIdLists: [[Int32]] = [[Int32(taggerCharVocab.encode(Self.rootToken))]]

        for form in tokens {
            wordIds.append(Int32(wordVocab.encode(form.lowercased())))
            let truncated = Array(form.prefix(Self.maxWordLen))
            let charIds = truncated.map { Int32(taggerCharVocab.encode(String($0))) }
            charIdLists.append(charIds.isEmpty ? [Int32(taggerCharVocab.unkId)] : charIds)
        }
        let maxWordLenInBatch = max(charIdLists.map { $0.count }.max() ?? 1, 1)

        let wordIdArray = try makeIntArray(wordIds, shape: [1, NSNumber(value: seqLen)])
        let charIdArray = try makeCharIdArray(charIdLists, maxWordLen: maxWordLenInBatch)

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "word_ids": MLFeatureValue(multiArray: wordIdArray),
            "char_ids": MLFeatureValue(multiArray: charIdArray),
        ])
        let output = try taggerModel.prediction(from: provider)

        // new version
        guard let uposLogits = output.featureValue(for: "upos_logits")?.multiArrayValue,
              let xposLogits = output.featureValue(for: "xpos_logits")?.multiArrayValue,
              let featsLogits = output.featureValue(for: "feats_logits")?.multiArrayValue,
              let arcLogits = output.featureValue(for: "arc_logits")?.multiArrayValue,
              let labelLogits = output.featureValue(for: "label_logits")?.multiArrayValue else {
            
            let info = output.featureNames.map { name -> String in
                let shape = output.featureValue(for: name)?.multiArrayValue?.shape ?? []
                return "\(name): \(shape)"
            }
            print(info)
            throw UDPipelineError.predictionFailed("missing expected model output type 310")
        }
        //need to get, decode UPOS so they can be passed to lemmatiser
        let decodedUpos = decodeUPOSInternal(uposLogits)
        // get the lemmas with the LemmatizerRunner() as runner
        let lemmas: [String]

        do {
            let runner = self.lemmatizerRunner
            lemmas = try tokens.enumerated().map { i, form in
                try runner.lemmatize(form: form, upos: decodedUpos[i])
            }
        } catch {
            // new error type to add
            throw UDPipelineError.lemmatizationFailed("lemmatizer failed: \(error)")
        }
    
        
        return TaggerRawOutput(
            sentence: sentence, seqLen: seqLen,
            uposLogits: uposLogits, xposLogits: xposLogits, featsLogits: featsLogits,
            decodedLemmas: lemmas, arcLogits: arcLogits, labelLogits: labelLogits
        )


    }

    // MARK: Step 2 (decode) -- UPOS
    private func decodeUPOSInternal(_ uposLogits: MLMultiArray) -> [String] {
        let seqLen = uposLogits.shape[1].intValue  // shape: [1, seqLen, vocabSize]
        return (1..<seqLen).map { t in
            let id = argmax(uposLogits, prefix: [0, t], dimSize: uposVocab.itos.count)
            return uposVocab.decode(id)
        }
    }
    /// One UPOS tag string per real word (indices 1..<seqLen), in order.
    private func decodeUPOS(_ raw: TaggerRawOutput) -> [String] {
        (1..<raw.seqLen).map { t in
            let id = argmax(raw.uposLogits, prefix: [0, t], dimSize: uposVocab.itos.count)
            return uposVocab.decode(id)
        }
    }

    // MARK: XPOS (not used at present, but here to make future mods easier if it's needed)
//    private func decodeXPOS(_ raw: TaggerRawOutput) -> [String] {
//        (1..<raw.seqLen).map { t in
//            let id = argmax(raw.xposLogits, prefix: [0, t], dimSize: xposVocab.itos.count)
//            return xposVocab.decode(id)
//        }
//    }

    // MARK: Step 3 (decode) -- lemmatisation with edit-script rule
    /// //NOTE: getLemmas uses the NEW lemmatizer.
    /// decodeLemmas function uses edit rules, and is here to enable easy roll-back, test, comparison
    /// One lemma string per real word, reconstructed by applying the
    /// predicted edit-script rule to that word's surface form.
//    private func decodeLemmas(_ raw: TaggerRawOutput) -> [String] {
//        zip(1..<raw.seqLen, raw.sentence.tokens).map { t, form in
//            let id = argmax(raw.lemmaLogits, prefix: [0, t], dimSize: lemmaRuleVocab.itos.count)
//            return applyLemmaRule(form: form, rule: lemmaRuleVocab.decode(id))
//        }
//    }
    private func getLemmas(_ raw: TaggerRawOutput) -> [String] {
        // set to true for dev test
        let dev = false
        var returnItem: [String]
        if dev {
            returnItem = []
            for item in raw.decodedLemmas{
                returnItem.append("dev_\(item)")
            }
        }
        else {
            returnItem = raw.decodedLemmas
        }
        return returnItem
    }
    // MARK: Step 4 (decode) -- morphological features
    private func decodeFeats(_ raw: TaggerRawOutput) -> [String] {
        (1..<raw.seqLen).map { t in
            let id = argmax(raw.featsLogits, prefix: [0, t], dimSize: featsVocab.itos.count)
            return featsVocab.decode(id)
        }
    }

    // MARK: Step 5 (decode) -- dependency parsing

    /// One (head, deprel) pair per real word, decoded via Chu-Liu-Edmonds
    /// (maximum spanning arborescence, rooted at node 0), which guarantees
    /// a valid, cycle-free dependency tree with a single root -- unlike a
    /// per-word greedy argmax, which can produce cycles or multiple roots.
    private func decodeDependencies(_ raw: TaggerRawOutput) -> [(head: Int, deprel: String)] {
        let n = raw.seqLen

        // Dense head-score matrix: scoreMatrix[h][d] = score of dependent d
        // attaching to head h. d == 0 (root can't be a dependent) and
        // h == d (a word can't be its own head) are left at -infinity and
        // are never read by the arc-selection loops below.
        var scoreMatrix = [[Double]](repeating: [Double](repeating: -Double.infinity, count: n), count: n)
        for d in 1..<n {
            for h in 0..<n where h != d {
                scoreMatrix[h][d] = raw.arcLogits[[0, d, h] as [NSNumber]].doubleValue
            }
        }

        let heads = solveArborescence(activeNodes: Array(0..<n), scoreMatrix: scoreMatrix)

        return (1..<n).map { t in
            // Every non-root node is guaranteed a parent by
            // solveArborescence; the `?? 0` fallback is defensive only.
            let head = heads[t] ?? 0

            var bestDeprelId = 0
            var bestDeprelScore = -Double.infinity
            for c in 0..<deprelVocab.itos.count {
                let v = raw.labelLogits[[0, c, t, head] as [NSNumber]].doubleValue
                if v > bestDeprelScore { bestDeprelScore = v; bestDeprelId = c }
            }
            return (head: head, deprel: deprelVocab.decode(bestDeprelId))
        }
    }

    // MARK: Chu-Liu-Edmonds maximum spanning arborescence

    /// Solves the maximum-weight spanning arborescence rooted at node 0
    /// over exactly `activeNodes` (which must include 0), using
    /// `scoreMatrix` for edge weights. Returns a map from every active node
    /// except 0 to its chosen parent (also an active node).
    ///
    /// This is a standard recursive implementation of Chu-Liu-Edmonds:
    /// greedily pick each node's best incoming edge; if that produces a
    /// cycle, contract the cycle into one representative node with
    /// reweighted edges, recurse on the smaller graph, then expand the
    /// result back out. Recursion terminates because each contraction
    /// strictly reduces the number of active nodes, and a graph with no
    /// cycle is returned immediately as-is.
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

        // Step 2: contract the cycle into a single representative node
        // (reusing the smallest node id in the cycle, rather than minting a
        // new one, keeps every id a real, meaningful node throughout).
        let cycleSet = Set(cycle)
        let representative = cycle.min()!

        // Total weight of the cycle's own internal edges -- used below to
        // work out the true cost of "breaking" the cycle at whichever node
        // ends up accepting an external edge instead.
        var cycleWeight = 0.0
        for v in cycle {
            cycleWeight += scoreMatrix[bestParent[v]!][v]
        }

        let newActiveNodes = activeNodes.filter { !cycleSet.contains($0) || $0 == representative }
        var newScoreMatrix = scoreMatrix

        // Bookkeeping so the contracted-graph result can be expanded back
        // into real node ids afterward.
        var enterFrom: [Int: Int] = [:] // u -> which cycle node the (u -> representative) edge really targets
        var exitTo: [Int: Int] = [:]    // w -> which cycle node the (representative -> w) edge really originates from

        for u in activeNodes where !cycleSet.contains(u) {
            var bestIn = -Double.infinity
            var bestVIn = -1
            var bestOut = -Double.infinity
            var bestVOut = -1
            for v in cycle {
                // Incoming: cost of accepting edge (u -> v) instead of v's
                // current in-cycle edge, while keeping every other cycle
                // edge intact.
                let reweighted = scoreMatrix[u][v] - scoreMatrix[bestParent[v]!][v] + cycleWeight
                if reweighted > bestIn { bestIn = reweighted; bestVIn = v }

                // Outgoing: plain best edge leaving the cycle to u -- no
                // reweighting needed, since which internal edge eventually
                // gets broken doesn't affect edges leaving the cycle.
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

        // Step 4: expand back. Every cycle node keeps its original in-cycle
        // parent, except the one node where an external edge broke the
        // cycle -- that node's real parent is whichever external node fed
        // into the cycle at that point.
        var result = contractedParents
        result.removeValue(forKey: representative)
        for v in cycle {
            result[v] = bestParent[v]
        }
        if let repParent = contractedParents[representative], let breakNode = enterFrom[repParent] {
            result[breakNode] = repParent
        }

        // Any outside node whose contracted parent came out as the
        // representative actually attaches to whichever real cycle node
        // achieved that best exit edge.
        for (node, parent) in contractedParents where parent == representative {
            if let realParent = exitTo[node] {
                result[node] = realParent
            }
        }

        return result
    }

    /// Finds one cycle among `bestParent`'s pointers, if any exists, by
    /// following each node's chain of parents and watching for a repeat.
    /// Returns the cycle as a list of the original node ids involved, or
    /// nil if the current bestParent pointers already form a valid tree.
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
    // MARK: end of new implementation of step5
  


    
    /*
     greedy,per-word argmax implementation : whole function in multiline quote
    // MARK: Step 5 (decode) -- dependency parsing  greedy implementation: One (head, deprel) pair per real word.
    /// NOTE : this is a placeholder algorithm, used to test whether this pipeline works :  no guarantee the tree is licit, correct
    ///
    private func decodeDependencies(_ raw: TaggerRawOutput) -> [(head: Int, deprel: String)] {
        (1..<raw.seqLen).map { t in
            var bestHead = 0
            var bestScore = -Double.infinity
            for h in 0..<raw.seqLen where h != t {
                let v = raw.arcLogits[[0, t, h] as [NSNumber]].doubleValue
                if v > bestScore { bestScore = v; bestHead = h }
            }

            var bestDeprelId = 0
            var bestDeprelScore = -Double.infinity
            for c in 0..<deprelVocab.itos.count {
                let v = raw.labelLogits[[0, c, t, bestHead] as [NSNumber]].doubleValue
                if v > bestDeprelScore { bestDeprelScore = v; bestDeprelId = c }
            }
            return (head: bestHead, deprel: deprelVocab.decode(bestDeprelId))
        }
    }
   */
     
    // MARK: Per-sentence processing: for progress-reporting callers
    /// Runs the same field-decoding logic as `run(text:level:mode:)`, but takes
    /// 1 tokenised sentence at a time, returning decoded `UDToken`
    func runOnSentence(_ sentence: TokenisedSentence, level: Int) throws -> [UDToken] {
        guard (1...5).contains(level) else {
            throw UDPipelineError.invalidLevel(level)
        }

        let n = sentence.tokens.count
        var lemmas = Array(repeating: "_", count: n)
        var uposTags = Array(repeating: "_", count: n)
        var featsTags = Array(repeating: "_", count: n)
        var heads = Array(repeating: "_", count: n)
        var deprels = Array(repeating: "_", count: n)

        if level >= 2 {
            let raw = try runTaggerParserModel(on: sentence)
            uposTags = decodeUPOS(raw)

            if level >= 3 {
                lemmas = getLemmas(raw)
            }
            if level >= 4 {
                featsTags = decodeFeats(raw)
            }
            if level >= 5 {
                let deps = decodeDependencies(raw)
                heads = deps.map { String($0.head) }
                deprels = deps.map { $0.deprel }
            }
        }

        return (0..<n).map { i in
            UDToken(
                tokid: i + 1, form: sentence.tokens[i], lemma: lemmas[i],
                upos: uposTags[i], xpos: "_", feats: featsTags[i],
                head: heads[i], deprel: deprels[i], col8: "_", col9: "_"
            )
        }
    }

    /// Formats tokens of one tagged sentence using the same `mode`
    /// rules as `run(text:level:mode:)`for `runOnSentence`
    func formatSentence(_ tokens: [UDToken], mode: String) throws -> [String] {
        var lines: [OutputLine] = tokens.map { .row($0) }
        lines.append(.blank)

        switch mode {
        case "raw":
            return formatRaw(lines)
        case "tidy":
            return formatTidy(lines)
        default:
            throw UDPipelineError.predictionFailed(
                "mode must be \"raw\" or \"tidy\" (got \"\(mode)\")"
            )
        }
    }

    // MARK: Controller

    /// Runs raw text through the pipeline up to (and including) `level`,
    /// and returns CoNLL-U-style lines (blank line between sentences).
    /// Fields beyond the requested level are left as "_", matching CoNLL-U
    /// convention for unannotated columns.
    ///
    ///   1 = tokenize only
    ///   2 = + UPOS
    ///   3 = + lemma
    ///   4 = + FEATS
    ///   5 = + dependency parsing (HEAD, DEPREL)
    ///
    /// XPOS is always "_" -- it wasn't one of the requested levels. See the
    /// file header if you want it added to a level.
    ///
    /// `mode` controls formatting, independent of `level`:
    ///   "raw"  -- plain tab-separated CoNLL-U fields (what a .conllu file
    ///             on disk actually looks like)
    ///   "tidy" -- the same fields, but column-aligned with padding so they
    ///             line up when displayed in a monospaced Text view
    func run(text: String, level: Int, mode: String) throws -> [String] {
        guard (1...5).contains(level) else {
            throw UDPipelineError.invalidLevel(level)
        }

        let sentences = try tokenize(text)
        var allLines: [OutputLine] = []

        for sentence in sentences {
            let tokens = try runOnSentence(sentence, level: level)
            for tok in tokens {
                allLines.append(.row(tok))
            }
            allLines.append(.blank)
        }

        switch mode {
        case "raw":
            return formatRaw(allLines)
        case "tidy":
            return formatTidy(allLines)
        default:
            throw UDPipelineError.predictionFailed(
                "mode must be \"raw\" or \"tidy\" (got \"\(mode)\")"
            )
        }
    }

    // MARK: - Output formatting


    private func formatRaw(_ lines: [OutputLine]) -> [String] {
        lines.map { line in
            switch line {
            case .row(let tok): return tok.conllRaw
            case .blank: return ""
            }
        }
    }

    /// Use string count to column-align rows of each sent  independently
    private func formatTidy(_ lines: [OutputLine]) -> [String] {
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
    
    /// One line of pipeline output, before formatting so  `formatTidy` can measure col widths
//    private enum OutputLine {
//        case row(UDToken)
//        case blank
//    }

}


enum OutputLine {
    case row(UDToken)
    case blank
}


