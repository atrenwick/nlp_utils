
import CoreML
import Foundation
import NaturalLanguage
import Combine


final class CNNBiLSTMPipeline: PipelineHelper, ObservableObject {
    // the actual pipeline for processing, with no optionals
    
    // heavy properties as constants, non-optional, as passed from loader and passed guard
    let tokenizerModel: MLModel
    let taggerModel: MLModel
    let lemmatizerRunner: LemmatizerRunner
    let tokenizerCharVocab: Vocab
    let wordVocab: Vocab
    let taggerCharVocab: Vocab
    let uposVocab: Vocab
    let featsVocab: Vocab
    let deprelVocab: Vocab
    let lemmaRuleVocab: Vocab

    // lightweight properties
    static let rootToken = "<root>"
    static let maxWordLen = 20 // matches tagger_parser/data.py's encode_sentence default
    let description = "I'm a CNN-BiLSTM pipeline"
    let maxWords: Int = 256

    private var runExplicit: Bool {
            UserDefaults.standard.bool(forKey: "runExplicit")
        }

    init(
        tokenizerModel: MLModel,
        taggerModel: MLModel,
        lemmatizerRunner: LemmatizerRunner,
        tokenizerCharVocab: Vocab,
        wordVocab: Vocab,
        taggerCharVocab: Vocab,
        uposVocab: Vocab,
        featsVocab: Vocab,
        deprelVocab: Vocab,
        lemmaRuleVocab: Vocab
    ) {
        self.tokenizerModel = tokenizerModel
        self.taggerModel = taggerModel
        self.lemmatizerRunner = lemmatizerRunner
        self.tokenizerCharVocab = tokenizerCharVocab
        self.wordVocab = wordVocab
        self.taggerCharVocab = taggerCharVocab
        self.uposVocab = uposVocab
        self.featsVocab = featsVocab
        self.deprelVocab = deprelVocab
        self.lemmaRuleVocab = lemmaRuleVocab
    }
    
    
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


// this is the loader - not designed to persist or be used for prediction
final class CNNBiLSTMPipelineLoader: ObservableObject, PipelineLoader {
    // 1. Published properties for UI progress meter to track
    @Published var loadingProgress: Double = min(1.0, 0.0)
    @Published var statusMessage: String = "Waiting to load..."
    @Published var loadingComplete: Bool = false
    
    // 2. The heavy properties are now optional 'var's, populated during async loading
    var tokenizerModel: MLModel?
    var taggerModel: MLModel?
    var lemmatizerRunner: LemmatizerRunner?
    
    var tokenizerCharVocab: Vocab?
    var wordVocab: Vocab?
    var taggerCharVocab: Vocab?
    var uposVocab: Vocab?
    var featsVocab: Vocab?
    var deprelVocab: Vocab?
    var lemmaRuleVocab: Vocab?
    
    // lightweight properties
    static let rootToken = "<root>"
    static let maxWordLen = 20 // matches tagger_parser/data.py's encode_sentence default
    let maxWords: Int = 256
    private var runExplicit: Bool {
        UserDefaults.standard.bool(forKey: "runExplicit")
    }
    
    // 3. LIGHTWEIGHT INIT
    init() {
    }
    func convertToRealPipeline(
        tokenizerModel: MLModel,
        taggerModel: MLModel,
        lemmatizerRunner: LemmatizerRunner,
        tokenizerCharVocab: Vocab,
        wordVocab: Vocab,
        taggerCharVocab: Vocab,
        uposVocab: Vocab,
        featsVocab: Vocab,
        deprelVocab: Vocab,
        lemmaRuleVocab: Vocab
    ) throws -> CNNBiLSTMPipeline {
        print("calling converter")
        return CNNBiLSTMPipeline(
            tokenizerModel: tokenizerModel,
            taggerModel: taggerModel,
            lemmatizerRunner: lemmatizerRunner,
            tokenizerCharVocab: tokenizerCharVocab,
            wordVocab: wordVocab,
            taggerCharVocab: taggerCharVocab,
            uposVocab: uposVocab,
            featsVocab: featsVocab,
            deprelVocab: deprelVocab,
            lemmaRuleVocab: lemmaRuleVocab
        )
    }
    @concurrent
    func loadCNNBiLSTMpipe(
        myConfig: TaggerConfig,
        onProgress: @MainActor @Sendable (Int, String) -> Void
    ) async throws -> CNNBiLSTMPipeline {
        let languageCode = myConfig.parsingConfig.selectedLanguage.rawValue
        let treebank = await myConfig.parsingConfig.selectedTreebank.short
        let myConfig: TaggerConfig = myConfig
        let tokenizerModel: MLModel?
        let taggerModel: MLModel?
        let tokenizerCharVocab: Vocab?
        let wordVocab: Vocab?
        let taggerCharVocab: Vocab?
        let uposVocab: Vocab?
        let featsVocab: Vocab?
        let deprelVocab: Vocab?
        let lemmaRuleVocab: Vocab?
        let lemmatizerRunner: LemmatizerRunner?
        
        // tokenizer model
        await onProgress(1, "Loading wordpiece tokenizer")
        tokenizerModel =  try await Self.loadMlpackage(named: "\(languageCode)_tokenizer_\(treebank)", myConfig: myConfig)
        
        // tagger model
        await onProgress(2, "Loading tagger")
        taggerModel = try await Self.loadMlpackage(named: "\(languageCode)_tagger_parser_\(treebank)", myConfig: myConfig)

        await onProgress(3, "Loading wordpiece vocab 1")
        tokenizerCharVocab = try await Vocab.load(named: "\(languageCode)_tokenizer_char_vocab_\(treebank)")

        await onProgress(4, "Loading wordpiece vocab 2")
        wordVocab = try await Vocab.load(named: "\(languageCode)_word_vocab_\(treebank)")

        await onProgress(5, "Loading wordpiece vocab 3")
        taggerCharVocab = try await Vocab.load(named: "\(languageCode)_tagger_char_vocab_\(treebank)")

        await onProgress(6, "Loading wordpiece vocab 4")
        uposVocab = try await Vocab.load(named: "\(languageCode)_upos_vocab_\(treebank)")

        await onProgress(7, "Loading wordpiece vocab 4")
        featsVocab = try await Vocab.load(named: "\(languageCode)_feats_vocab_\(treebank)")

        await onProgress(8, "Loading wordpiece vocab 4")
        deprelVocab = try await Vocab.load(named: "\(languageCode)_deprel_vocab_\(treebank)")

        await onProgress(9, "Loading lemmarule vocab")
        lemmaRuleVocab = try await Vocab.load(named: "\(languageCode)_lemma_rule_vocab_\(treebank)")

        await onProgress(10, "Loading neural lemmatizer")
        lemmatizerRunner = try await LemmatizerRunner(languageCode: languageCode, treebank: treebank)

        print("seems to have succeeeded")
        
        // Step 3: Assign to properties and mark ready

        guard let tokenizerModel = tokenizerModel, let taggerModel = taggerModel, let lemmatizerRunner = lemmatizerRunner, let tokenizerCharVocab = tokenizerCharVocab, let wordVocab = wordVocab, let taggerCharVocab = taggerCharVocab, let uposVocab = uposVocab, let featsVocab = featsVocab, let deprelVocab = deprelVocab, let lemmaRuleVocab = lemmaRuleVocab else { throw PipelineError.notReadyToSendToRunner }
        return try await convertToRealPipeline(
            tokenizerModel: tokenizerModel,
            taggerModel: taggerModel,
            lemmatizerRunner: lemmatizerRunner,
            tokenizerCharVocab: tokenizerCharVocab,
            wordVocab: wordVocab,
            taggerCharVocab: taggerCharVocab,
            uposVocab: uposVocab,
            featsVocab: featsVocab,
            deprelVocab: deprelVocab,
            lemmaRuleVocab: lemmaRuleVocab
        )
    }
}

