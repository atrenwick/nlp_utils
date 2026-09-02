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
//
// MARK: - Errors

enum AllUpUDPipelineError: Error, LocalizedError {
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
final class AllUpUDPipeline {
    static let rootToken = "<root>"
    static let maxWordLen = 20

    private let tokenizerModel: MLModel
    private let taggerModel: MLModel
    private let lemmatizerRunner: LemmatizerRunner

    private let tokenizerCharVocab: Vocab
    private let wordVocab: Vocab
    private let taggerCharVocab: Vocab
    private let uposVocab: Vocab
    private let xposVocab: Vocab
    private let featsVocab: Vocab
    private let deprelVocab: Vocab
//    private let lemmaRuleVocab: Vocab

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
//        lemmaRuleVocab = try Vocab.load(named: "ignoreF_R_lemma_rule_vocab")
        self.lemmatizerRunner = try LemmatizerRunner()
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
            let runner = try LemmatizerRunner()
            lemmas = try tokens.enumerated().map { i, form in
                //TODO: need to load this LemmatizerRunner :: class - instance
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
                //lemmas = decodeLemmas(raw) get lemmas using rule based lemmatiser
                lemmas = getLemmas(raw) // get lemmas with new model
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

//MARK: lemmatizer runner :
//TODO: change hardcoded paths >>>> forResource <<<< when EN model trained
final class LemmatizerRunner {

    private let encoder: MLModel
    private let decoderStep: MLModel

    private let charStoi: [String: Int]
    private let charItos: [String]
    private let uposStoi: [String: Int]

    private let padId: Int
    private let unkId: Int
    private let bosId: Int
    private let eosId: Int

    private let lemmaDict: [String: String]

    private let maxLemmaLen = 32    // Must match MAX_SRC_LEN in convert_lemmatizer.py
    private let maxSrcLen = 32

    init() throws {
        guard let encoderURL = Bundle.main.url(forResource: "FR_neuralLemmatizerEncoder", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "FR_neuralLemmatizerEncoder", withExtension: "mlpackage") else {
            throw LemmatizerError.resourceMissing("FR_neuralLemmatizerEncoder")
        }
        guard let decoderURL = Bundle.main.url(forResource: "FR_neuralLemmatizerDecoderStep", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "FR_neuralLemmatizerDecoderStep", withExtension: "mlpackage") else {
            throw LemmatizerError.resourceMissing("FR_neuralLemmatizerDecoderStep")
        }

        do {
            self.encoder = try MLModel(contentsOf: encoderURL)
            self.decoderStep = try MLModel(contentsOf: decoderURL)
        } catch {
            throw LemmatizerError.modelLoadFailed(error.localizedDescription)
        }

        // --- Load vocabularies -------------------------------------------------
        guard let vocabsURL = Bundle.main.url(forResource: "FR_neurallemma_vocabs", withExtension: "json") else {
            throw LemmatizerError.resourceMissing("FR_neurallemma_vocabs.json")
        }
        let vocabsData = try Data(contentsOf: vocabsURL)
        let vocabs = try JSONDecoder().decode(LemmaVocabs.self, from: vocabsData)

        self.charItos = vocabs.char
        var cs: [String: Int] = [:]
        for (i, c) in vocabs.char.enumerated() { cs[c] = i }
        self.charStoi = cs

        var us: [String: Int] = [:]
        for (i, u) in vocabs.upos.enumerated() { us[u] = i }
        self.uposStoi = us

        self.padId = cs["<pad>"] ?? 0
        self.unkId = cs["<unk>"] ?? 1
        self.bosId = cs["<bos>"] ?? 2
        self.eosId = cs["<eos>"] ?? 3

        // --- Load the frequency dictionary --------------------------------------
        guard let dictURL = Bundle.main.url(forResource: "FR_neurallemma_dict", withExtension: "json") else {
            throw LemmatizerError.resourceMissing("FR_neurallemma_dict.json")
        }
        let dictData = try Data(contentsOf: dictURL)
        self.lemmaDict = try JSONDecoder().decode([String: String].self, from: dictData)
    }

    /// Look up or predict the lemma for a single (form, UPOS) pair.
    func lemmatize(form: String, upos: String) throws -> String {
        let key = "\(form.lowercased())|\(upos)"
        if let dictLemma = lemmaDict[key] {
            return dictLemma
        }
        return try neuralLemmatize(form: form, upos: upos)
    }

    /// Convenience for a whole sentence at once.
    func lemmatize(forms: [String], uposTags: [String]) throws -> [String] {
        precondition(forms.count == uposTags.count, "forms and uposTags must be the same length")
        return try zip(forms, uposTags).map { try lemmatize(form: $0, upos: $1) }
    }

    // ------------------------------------------------------------------------
    // Neural fallback: run the encoder once, then loop the decoder step.
    // ------------------------------------------------------------------------

    private func neuralLemmatize(form: String, upos: String) throws -> String {
        let rawIds = try form.lowercased().map { char -> Int in
            let s = String(char)
            guard let id = charStoi[s] else { return unkId }
            return id
        }
        guard !rawIds.isEmpty else { return form }

        // Pad/truncate to `convert_lemmatizer.py`'s MAX_SRC_LEN
        let realLen = min(rawIds.count, maxSrcLen)
        var srcIds = Array(rawIds.prefix(maxSrcLen))
        while srcIds.count < maxSrcLen { srcIds.append(padId) }

        let uposId = uposStoi[upos] ?? 0

        // --- Encoder pass ----------------------------------------------------
        let srcArray = try MLMultiArray(shape: [1, NSNumber(value: maxSrcLen)], dataType: .int32)
        for (i, id) in srcIds.enumerated() { srcArray[[0, i] as [NSNumber]] = NSNumber(value: id) }

        let maskArray = try MLMultiArray(shape: [1, NSNumber(value: maxSrcLen)], dataType: .int32)
        for i in 0..<maxSrcLen {
            maskArray[[0, i] as [NSNumber]] = NSNumber(value: i < realLen ? 1 : 0)
        }

        let uposArray = try MLMultiArray(shape: [1], dataType: .int32)
        uposArray[[0] as [NSNumber]] = NSNumber(value: uposId)

        let encoderInput = try MLDictionaryFeatureProvider(dictionary: [
            "src": srcArray,
            "mask": maskArray,
            "upos": uposArray,
        ])
        let encoderOutput = try encoder.prediction(from: encoderInput)

        guard let encOut = encoderOutput.featureValue(for: "enc_out")?.multiArrayValue,
              var h = encoderOutput.featureValue(for: "init_h")?.multiArrayValue,
              var c = encoderOutput.featureValue(for: "init_c")?.multiArrayValue else {
            throw LemmatizerError.modelLoadFailed("encoder output missing expected fields type 154")
        }

        // --- Decoder loop ------------------------------------------------------
        var curCharId = bosId
        var outputChars: [String] = []

        for _ in 0..<maxLemmaLen {
            let curArray = try MLMultiArray(shape: [1], dataType: .int32)
            curArray[[0] as [NSNumber]] = NSNumber(value: curCharId)

            let stepInput = try MLDictionaryFeatureProvider(dictionary: [
                "cur_char": curArray,
                "h": h,
                "c": c,
                "enc_out": encOut,
                "mask": maskArray,
            ])
            let stepOutput = try decoderStep.prediction(from: stepInput)

            guard let logits = stepOutput.featureValue(for: "logits")?.multiArrayValue,
                  let newH = stepOutput.featureValue(for: "new_h")?.multiArrayValue,
                  let newC = stepOutput.featureValue(for: "new_c")?.multiArrayValue else {
                throw LemmatizerError.modelLoadFailed("decoder step output missing expected fields type 177")
            }

            let nextId = argmax(logits)
            if nextId == eosId { break }
            if nextId != padId && nextId != bosId && nextId != unkId {
                outputChars.append(charItos.indices.contains(nextId) ? charItos[nextId] : "")
            } else if nextId == unkId {
                // Model was unsure of this character; skip rather than
                // inserting a literal "<unk>" into the lemma.
            }

            curCharId = nextId
            h = newH
            c = newC
        }

        let lemma = outputChars.joined()
        return lemma.isEmpty ? form : lemma
    }

    private func argmax(_ array: MLMultiArray) -> Int {
        let count = array.count
        var bestIdx = 0
        var bestVal = -Float.greatestFiniteMagnitude
        for i in 0..<count {
            let v = array[i].floatValue
            if v > bestVal {
                bestVal = v
                bestIdx = i
            }
        }
        return bestIdx
    }
}


enum LemmatizerError: Error {
    case modelLoadFailed(String)
    case resourceMissing(String)
    case unknownChar(Character)
}

struct LemmaVocabs: Codable {
    let char: [String]
    let upos: [String]
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
