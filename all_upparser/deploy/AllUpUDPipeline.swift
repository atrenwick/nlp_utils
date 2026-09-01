import CoreML
import Foundation


// MARK: - Vocabulary
structure to decode the vocab data JSON file
private struct VocabData: Decodable {
   let itos: [String]
   let pad: String
   let unk: String
}
define the vocab class
final class Vocab {
   let itos: [String]
   let stoi: [String: Int]
   let pad: String
   let unk: String

   //init method for the vocab class
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

func to get path to file, load, decode and return decoded data based on name of json file
   static func load(named name: String, bundle: Bundle = .main) throws -> Vocab {
       guard let url = bundle.url(forResource: name, withExtension: "json") else {
           throw AllUpUDPipelineError.missingResource("\(name).json")
       }
       let data = try Data(contentsOf: url)
       let decoded = try JSONDecoder().decode(VocabData.self, from: data)
       return Vocab(data: decoded)
   }
}

// MARK: - Tokenizer output
struct TokenisedSentence: Hashable {
   let id: String
   let tokens: [String]
}

// MARK: - Tagged output
struct UDToken : Identifiable {
   var id = UUID()
   let tokid: Int
   let form: String
   let lemma: String
   let upos: String
   let xpos: String
   let feats: String
   let head: String
   let deprel: String
   let col8: String
   let col9: String
   /// Tab-separated, in CoNLL-U column order (ID FORM LEMMA UPOS XPOS FEATS HEAD DEPREL).
   var conlluLine: String {
       [String(tokid), form, lemma, upos, xpos, feats, head, deprel].joined(separator: "\t")
   }
   var conllRaw: String{
       [String(tokid), form, lemma, upos, xpos, feats, head, deprel, "_","_"].joined(separator: "\t") + "\n"
   }
}

// MARK: - Errors

enum AllUpUDPipelineError: Error, LocalizedError {
    case missingResource(String)
    case modelLoadFailed(String)
    case predictionFailed(String)
    case invalidLevel(Int)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "Missing bundled resource: \(name). Did you add it to the app target?"
        case .modelLoadFailed(let name):
            return "Failed to load Core ML model '\(name)'. Did you add \(name).mlpackage to the app target?"
        case .predictionFailed(let msg):
            return "Prediction failed: \(msg)"
        case .invalidLevel(let level):
            return "Invalid pipeline level \(level): must be between 1 and 5."
        }
    }
}


// MARK: - Pipeline
final class AllUpUDPipeline {
    static let rootToken = "<root>"
    static let maxWordLen = 20

    private let tokenizerModel: MLModel
    private let taggerModel: MLModel

    private let tokenizerCharVocab: Vocab
    private let wordVocab: Vocab
    private let taggerCharVocab: Vocab
    private let uposVocab: Vocab
    private let xposVocab: Vocab
    private let featsVocab: Vocab
    private let deprelVocab: Vocab
    private let lemmaRuleVocab: Vocab

    init() throws {
        tokenizerModel = try Self.loadModel(named: "FR_tokenizer")
        taggerModel = try Self.loadModel(named: "FR_tagger_parser")

        tokenizerCharVocab = try Vocab.load(named: "FR_tokenizer_char_vocab")
        wordVocab = try Vocab.load(named: "FR_word_vocab")
        taggerCharVocab = try Vocab.load(named: "FR_tagger_char_vocab")
        uposVocab = try Vocab.load(named: "FR_upos_vocab")
        xposVocab = try Vocab.load(named: "FR_xpos_vocab")
        featsVocab = try Vocab.load(named: "FR_feats_vocab")
        deprelVocab = try Vocab.load(named: "FR_deprel_vocab")
        lemmaRuleVocab = try Vocab.load(named: "FR_lemma_rule_vocab")
    }

    private static func loadModel(named name: String) throws -> MLModel {
        // Xcode compiles a bundled .mlpackage into a .mlmodelc at build
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            throw AllUpUDPipelineError.modelLoadFailed(name)
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
            throw AllUpUDPipelineError.predictionFailed("tokenizer produced no 'logits' output")
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
        let lemmaLogits: MLMultiArray
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

        guard
            let uposLogits = output.featureValue(for: "upos_logits")?.multiArrayValue,
            let xposLogits = output.featureValue(for: "xpos_logits")?.multiArrayValue,
            let featsLogits = output.featureValue(for: "feats_logits")?.multiArrayValue,
            let lemmaLogits = output.featureValue(for: "lemma_rule_logits")?.multiArrayValue,
            let arcLogits = output.featureValue(for: "arc_logits")?.multiArrayValue,
            let labelLogits = output.featureValue(for: "label_logits")?.multiArrayValue
        else {
            throw AllUpUDPipelineError.predictionFailed("tagger_parser produced missing output(s)")
        }

        return TaggerRawOutput(
            sentence: sentence, seqLen: seqLen,
            uposLogits: uposLogits, xposLogits: xposLogits, featsLogits: featsLogits,
            lemmaLogits: lemmaLogits, arcLogits: arcLogits, labelLogits: labelLogits
        )
    }

    // MARK: Step 2 (decode) -- UPOS
    private func decodeUPOS(_ raw: TaggerRawOutput) -> [String] {
        (1..<raw.seqLen).map { t in
            let id = argmax(raw.uposLogits, prefix: [0, t], dimSize: uposVocab.itos.count)
            return uposVocab.decode(id)
        }
    }

    // MARK: XPOS (not used at present, but here to make future mods easier if it's needed)
    private func decodeXPOS(_ raw: TaggerRawOutput) -> [String] {
        (1..<raw.seqLen).map { t in
            let id = argmax(raw.xposLogits, prefix: [0, t], dimSize: xposVocab.itos.count)
            return xposVocab.decode(id)
        }
    }

    // MARK: Step 3 (decode) -- lemmatisation with edit-script rule
    private func decodeLemmas(_ raw: TaggerRawOutput) -> [String] {
        zip(1..<raw.seqLen, raw.sentence.tokens).map { t, form in
            let id = argmax(raw.lemmaLogits, prefix: [0, t], dimSize: lemmaRuleVocab.itos.count)
            return applyLemmaRule(form: form, rule: lemmaRuleVocab.decode(id))
        }
    }

    // MARK: Step 4 (decode) -- morphological features
    private func decodeFeats(_ raw: TaggerRawOutput) -> [String] {
        (1..<raw.seqLen).map { t in
            let id = argmax(raw.featsLogits, prefix: [0, t], dimSize: featsVocab.itos.count)
            return featsVocab.decode(id)
        }
    }

    // MARK: Step 5 (decode) -- dependency parsing : One (head, deprel) pair per real word.
    /// NOTE : this is a placeholder algorithm, used to test whether this pipeline works :  no guarantee the tree is licit, correct
    /// TODO: change out for proper max-spanning tree
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

    // MARK: Per-sentence processing: for progress-reporting callers
    /// Runs the same field-decoding logic as `run(text:level:mode:)`, but takes
    /// 1 tokenised sentence at a time, returning decoded `UDToken`
    func runOnSentence(_ sentence: TokenisedSentence, level: Int) throws -> [UDToken] {
        guard (1...5).contains(level) else {
            throw AllUpUDPipelineError.invalidLevel(level)
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
                lemmas = decodeLemmas(raw)
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
        lines.append(.blank) // blank line appened to match separator convention with `run` method

        switch mode {
        case "raw":
            return formatRaw(lines)
        case "tidy":
            return formatTidy(lines)
        default:
            throw AllUpUDPipelineError.predictionFailed(
                "mode must be \"raw\" or \"tidy\" (got \"\(mode)\")"
            )
        }
    }

    // MARK: Controller

    /// Runs pipeline up to and including `level`,
    /// Returns CoNLL-U-style lines (blank line between sentences).
    /// Fields beyond the requested level are left as "_",
    ///
    ///   1 = tokenize only
    ///   2 = + UPOS
    ///   3 = + lemma
    ///   4 = + FEATS
    ///   5 = + dependency parsing (HEAD, DEPREL)
    ///
    /// Note : XPOS isn't an option as no XPOS training data was used
    ///
    /// `mode` controls formatting, independent of `level`:
    ///   "raw"  -- plain tab-separated CoNLL-U fields (what a .conllu file
    ///             on disk actually looks like)
    ///   "tidy" -- the same fields, but column-aligned with padding so they
    ///             line up when displayed in a monospaced Text view
    func run(text: String, level: Int, mode: String) throws -> [String] {
        guard (1...5).contains(level) else {
            throw AllUpUDPipelineError.invalidLevel(level)
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
            throw AllUpUDPipelineError.predictionFailed(
                "mode must be \"raw\" or \"tidy\" (got \"\(mode)\")"
            )
        }
    }

    // MARK: - Output formatting

    /// One line of pipeline output, before formatting so  `formatTidy` can measure col widths
    private enum OutputLine {
        case row(UDToken)
        case blank
    }

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
}

// MARK: - MLMultiArray helpers

private func makeIntArray(_ values: [Int32], shape: [NSNumber]) throws -> MLMultiArray {
    let arr = try MLMultiArray(shape: shape, dataType: .int32)
    for (i, v) in values.enumerated() {
        arr[i] = NSNumber(value: v)
    }
    return arr
}

private func makeCharIdArray(_ charIdLists: [[Int32]], maxWordLen: Int) throws -> MLMultiArray {
    let t = charIdLists.count
    let arr = try MLMultiArray(
        shape: [1, NSNumber(value: t), NSNumber(value: maxWordLen)], dataType: .int32
    )
    for i in 0..<arr.count { arr[i] = 0 } // pad_id is always 0 by Vocab convention
    for (wi, ids) in charIdLists.enumerated() {
        for (ci, cid) in ids.enumerated() {
            arr[[0, wi, ci] as [NSNumber]] = NSNumber(value: cid)
        }
    }
    return arr
}

private func argmax(_ arr: MLMultiArray, prefix: [Int], dimSize: Int) -> Int {
    var best = 0
    var bestVal = -Double.infinity
    for c in 0..<dimSize {
        let idx = (prefix + [c]).map { NSNumber(value: $0) }
        let v = arr[idx].doubleValue
        if v > bestVal { bestVal = v; best = c }
    }
    return best
}
