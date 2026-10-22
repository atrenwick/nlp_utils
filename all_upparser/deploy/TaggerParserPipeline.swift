
import CoreML
import Foundation
import NaturalLanguage

// MARK: - Pipeline
//TODO: add choice of lemmatisation method - rule/hybrid for cnnbilstm :: choose primary lemmas as col2, option is sec lemma as col8
///     :add option of multiple lemmas predicted on same run, send extra to spec column
final class CNNBiLSTMPipeline: PipelineHelper {
    static let rootToken = "<root>"
    static let maxWordLen = 20 // matches tagger_parser/data.py's encode_sentence default
    let description: String
    let maxWords: Int = 256
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
    private let lemmaRuleVocab: Vocab
    // computed property of class to read from runExplicit every time a method runs
    private var runExplicit: Bool {
            UserDefaults.standard.bool(forKey: "runExplicit")
        }
    init(myConfig: TaggerConfig) throws {
        //    init(languageCode: String, treebank: String) throws {
        let languageCode = myConfig.parsingConfig.selectedLanguage.rawValue
        let treebank = myConfig.parsingConfig.selectedTreebank.short
        description = "I'm a CNN-BiLSTM pipeline"
        switch myConfig.parsingConfig.modelArchitecture {
        case .cnnBiLSTM:
            tokenizerModel = try Self.loadMlpackage(named: "\(languageCode)_tokenizer_\(treebank)", myConfig: myConfig)
            taggerModel = try Self.loadMlpackage(named: "\(languageCode)_tagger_parser_\(treebank)", myConfig: myConfig)
            
            tokenizerCharVocab = try Vocab.load(named: "\(languageCode)_tokenizer_char_vocab_\(treebank)")
            wordVocab = try Vocab.load(named: "\(languageCode)_word_vocab_\(treebank)")
            taggerCharVocab = try Vocab.load(named: "\(languageCode)_tagger_char_vocab_\(treebank)")
            uposVocab = try Vocab.load(named: "\(languageCode)_upos_vocab_\(treebank)")
            //xposVocab = try Vocab.load(named: "\(languageCode)_xpos_vocab\(treebank)")
            featsVocab = try Vocab.load(named: "\(languageCode)_feats_vocab_\(treebank)")
            deprelVocab = try Vocab.load(named: "\(languageCode)_deprel_vocab_\(treebank)")
            lemmaRuleVocab = try Vocab.load(named: "\(languageCode)_lemma_rule_vocab_\(treebank)")
            self.lemmatizerRunner = try LemmatizerRunner(languageCode: languageCode, treebank: treebank)
        default :
            throw PipelineError.architectureConflict
        }
    }
    // prefer static func on UDPipelineBERTBased ->> loadMlpackage
//    private static func loadModel(named name: String) throws -> MLModel {
//        // Xcode compiles a bundled .mlpackage into a .mlmodelc at build
//        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
//            throw PipelineError.modelLoadFailed(name)
//        }
//        return try MLModel(contentsOf: url)
//    }

    // MARK: Step 1 -- character-level tokenizer / sentence segmenter
    /// Run raw text through tokenizer model, returning 1x [HashableSent] per sent, numbered 1->
    func tokenize(_ text: String) throws -> [HashableSentence] {
        let chars = Array(text)
        guard !chars.isEmpty else { return [] }

        let ids = chars.map { Int32(tokenizerCharVocab.encode(String($0))) }
        let inputArray = try makeIntArray(ids, shape: [1, NSNumber(value: ids.count)])
        let provider = try MLDictionaryFeatureProvider(
            dictionary: ["char_ids": MLFeatureValue(multiArray: inputArray)]
        )
        let output = try tokenizerModel.prediction(from: provider)
        guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
            throw PipelineError.tokenizationFail("tokenizer produced no 'logits' output")
        }

        var tokenLists: [[String]] = []
        var currentSentence: [String] = []
        var currentWord = ""

        for (i, ch) in chars.enumerated() {
            let label = parserArgmax(logits, prefix: [0, i], dimSize: 4)
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
            HashableSentence(id: String(i + 1), tokens: tokens, conllMetas: [])
        }
    }

    // MARK: Step 2 -- run the tagger-parser

    private func runTaggerParserModel(on sentence: HashableSentence) throws -> TaggerRawOutput {
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
              let ruleLemmaLogits = output.featureValue(for:"lemma_rule_logits")?.multiArrayValue,
              let featsLogits = output.featureValue(for: "feats_logits")?.multiArrayValue,
              let arcLogits = output.featureValue(for: "arc_logits")?.multiArrayValue,
              let labelLogits = output.featureValue(for: "label_logits")?.multiArrayValue else {
            
            let info = output.featureNames.map { name -> String in
                let shape = output.featureValue(for: name)?.multiArrayValue?.shape ?? []
                return "\(name): \(shape)"
            }
            if runExplicit {
                print(info)
            }
            throw PipelineError.predictionFailedAtLogits("missing expected model output type 310 :: getting from logits")
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
            throw PipelineError.lemmatizationFailed("lemmatizer failed: \(error)")
        }
//        print("Report267::")
//        print("Sentence == \(sentence)")
//        
//        print("seqlen == \(seqLen)")
//        for item in [uposLogits, xposLogits, featsLogits, ruleLemmaLogits,  arcLogits, labelLogits]{
//            print("\(item) :: , \(item.count)")
//        }
//        print ("Neural lemmas == \(lemmas.count)")
        return TaggerRawOutput(
            sentence: sentence, seqLen: seqLen,
            uposLogits: uposLogits, xposLogits: xposLogits, featsLogits: featsLogits, ruleLemmaLogits: ruleLemmaLogits,
            decodedLemmas: lemmas, arcLogits: arcLogits, labelLogits: labelLogits
        )
    }

    // MARK: Step 2 (decode) -- UPOS
    private func decodeUPOSInternal(_ uposLogits: MLMultiArray) -> [String] {
        let seqLen = uposLogits.shape[1].intValue  // shape: [1, seqLen, vocabSize]
        return (1..<seqLen).map { t in
            let id = parserArgmax(uposLogits, prefix: [0, t], dimSize: uposVocab.itos.count)
            return uposVocab.decode(id)
        }
    }
    /// One UPOS tag string per real word (indices 1..<seqLen), in order.
    private func decodeUPOS(_ raw: TaggerRawOutput) -> [String] {
        (1..<raw.seqLen).map { t in
            let id = parserArgmax(raw.uposLogits, prefix: [0, t], dimSize: uposVocab.itos.count)
            return uposVocab.decode(id)
        }
    }

    // MARK: XPOS (not used at present, but here to make future mods easier if it's needed)
//    private func decodeXPOS(_ raw: TaggerRawOutput) -> [String] {
//        (1..<raw.seqLen).map { t in
//            let id = parserArgmax(raw.xposLogits, prefix: [0, t], dimSize: xposVocab.itos.count)
//            return xposVocab.decode(id)
//        }
//    }

    // MARK: Step 3 (decode) -- lemmatisation with edit-script rule
    /// 1x lemma string per real word, made by applying the predicted edit-script rule to word's raw form.
    ///
    func decodeRuleLemmas(_ raw: TaggerRawOutput) -> [String] {
        zip(1..<raw.seqLen, raw.sentence.tokens).map { t, form in
            let id = parserArgmax(raw.ruleLemmaLogits, prefix: [0, t], dimSize: lemmaRuleVocab.itos.count)
            return applyLemmaRule(form: form, rule: lemmaRuleVocab.decode(id))
        }
    }

    // decode rule lemmas moved to UDDecoding extension via protocol 
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
            let id = parserArgmax(raw.featsLogits, prefix: [0, t], dimSize: featsVocab.itos.count)
            return featsVocab.decode(id)
        }
    }

    // MARK: Step 5 (decode) -- dependency parsing
    // now in extension via protocol
    private func decodeDependencies(_ raw: TaggerRawOutput) -> [(head: Int, deprel: String)] {
        decodeParse(
            runExplicit: true,
            wordCount: raw.seqLen - 1,
            deprelVocab: deprelVocab,
            arcScore: { d, h in raw.arcLogits[[0, d, h] as [NSNumber]].doubleValue },
            labelScore: { c, t, head in raw.labelLogits[[0, c, t, head] as [NSNumber]].doubleValue }
        )
    }


    // MARK: Per-sentence processing: for progress-reporting callers
    /// same field-decoding logic as `run(text:level:mode:)`,with 1x tokenised sent a time ->Token
    func runOnSentence(_ sentence: HashableSentence,  myConfig: TaggerConfig)  -> OnSentResult {
        if runExplicit { print("running on sents with CNN-BiLSTM pipeline") }
        let wordPieceCount = -5
        guard !sentence.tokens.isEmpty else {
            return OnSentResult(sentence: sentence, subtokCount: wordPieceCount, resultType: .empty, decoded: [])
        }
        // check under word limit for model
        guard sentence.tokens.count < maxWords else {
            return OnSentResult(sentence: sentence, subtokCount: wordPieceCount, resultType: .tooManyWords, decoded: [])
        }

        let n = sentence.tokens.count
        let level = myConfig.parsingConfig.maxPipelineStep.rawValue
        var uposTags = Array(repeating: "_", count: n)
        var featsTags = Array(repeating: "_", count: n)
        var heads = Array(repeating: "_", count: n)
        var deprels = Array(repeating: "_", count: n)
        var primaryLemmas = Array(repeating: "_", count: n)
        var secondaryLemmas = Array(repeating: "_", count: n)

        do {
            if level >= 2 {
                let raw = try runTaggerParserModel(on: sentence)
                uposTags = decodeUPOS(raw)
                if level >= 3 {

                    switch myConfig.parsingConfig.priLemSource {
                    case .hybrid:
                        primaryLemmas = getLemmas(raw)
                        if myConfig.parsingConfig.getSecLems{
                            secondaryLemmas = decodeRuleLemmas(raw)
                        }
                    case .rule:
                        primaryLemmas = decodeRuleLemmas(raw)
                        if myConfig.parsingConfig.getSecLems{
                            secondaryLemmas = getLemmas(raw)
                        }
                    }
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

            let tokens = (0..<n).map { i in
                Token(
                    tokid: i + 1,
                    form: sentence.tokens[i],
                    lemma: primaryLemmas[i],
                    upos: uposTags[i],
                    xpos: "_",
                    feats: featsTags[i],
                    head: heads[i],
                    deprel: deprels[i],
                    col8: myConfig.parsingConfig.getSecLems ? secondaryLemmas[i] : "_",
                    col9: "_",
                    subTokens: []
                )
            }
            return OnSentResult(sentence: sentence, subtokCount: wordPieceCount, resultType: .success, decoded: tokens)
        } catch {
            if runExplicit { print("sentence failed: \(error.localizedDescription)") }
            return OnSentResult(sentence: sentence, subtokCount: wordPieceCount, resultType: .otherError, decoded: [])

        }
    }
    
    //    func runOnSentenceOrig(_ sentence: HashableSentence,  myConfig: TaggerConfig) throws -> [Token] {
//        let level = myConfig.parsingConfig.maxPipelineStep.rawValue
//        guard (1...5).contains(level) else {
//            throw PipelineError.invalidLevel(level)
//        }
//
//        let n = sentence.tokens.count
//        
//        var uposTags = Array(repeating: "_", count: n)
//        var featsTags = Array(repeating: "_", count: n)
//        var heads = Array(repeating: "_", count: n)
//        var deprels = Array(repeating: "_", count: n)
//        var primaryLemmas = Array(repeating: "_", count: n)
//        var secondaryLemmas = Array(repeating: "_", count: n)
//
//        if level >= 2 {
//            let raw = try runTaggerParserModel(on: sentence)
//            uposTags = decodeUPOS(raw)
//            if level >= 3 {
//
//                switch myConfig.parsingConfig.priLemSource {
//                case .hybrid:
//                    primaryLemmas = getLemmas(raw)
//                    if myConfig.parsingConfig.getSecLems{
//                        secondaryLemmas = decodeRuleLemmas(raw)
//                    }
//                case .rule:
//                    primaryLemmas = decodeRuleLemmas(raw)
//                    if myConfig.parsingConfig.getSecLems{
//                        secondaryLemmas = getLemmas(raw)
//                    }
//                }
//            }
//            if level >= 4 {
//                featsTags = decodeFeats(raw)
//            }
//            if level >= 5 {
//                let deps = decodeDependencies(raw)
//                heads = deps.map { String($0.head) }
//                deprels = deps.map { $0.deprel }
//            }
//        }
//
//        return (0..<n).map { i in
//            Token(
//                tokid: i + 1, form: sentence.tokens[i], lemma: primaryLemmas[i],
//                upos: uposTags[i], xpos: "_", feats: featsTags[i],
//                head: heads[i], deprel: deprels[i], col8: myConfig.parsingConfig.getSecLems ? secondaryLemmas[i] : "_", col9: "_", subTokens: []
//            )
//        }
//    }



    func makeIntArray(_ values: [Int32], shape: [NSNumber]) throws -> MLMultiArray {
        let arr = try MLMultiArray(shape: shape, dataType: .int32)
        for (i, v) in values.enumerated() {
            arr[i] = NSNumber(value: v)
        }
        return arr
    }

    func makeCharIdArray(_ charIdLists: [[Int32]], maxWordLen: Int) throws -> MLMultiArray {
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
    
    func parserArgmax(_ arr: MLMultiArray, prefix: [Int], dimSize: Int) -> Int {
        var best = 0
        var bestVal = -Double.infinity
        for c in 0..<dimSize {
            let idx = (prefix + [c]).map { NSNumber(value: $0) }
            let v = arr[idx].doubleValue
            if v > bestVal {
                bestVal = v
                best = c
            }
        }
        return best
    }
}
