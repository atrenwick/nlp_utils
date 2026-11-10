
import CoreML
import Foundation
import NaturalLanguage
import Combine

/// the actual CNNBiLSTMPipeline for processing, with no optionals
final class CNNBiLSTMPipeline: PipelineHelper, LinguisticProcessingHelper, ObservableObject {
    // no change
    var seqLen: Int = 256
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
    static let rootToken = "<root>"
    static let maxWordLen = 20 // same as tagger_parser/data.py's encode_sentence default
    let description = "I'm a CNN-BiLSTM pipeline"
    let maxWords: Int = 256 // prefer parse // extract from metas

    internal var runExplicit: Bool {
        UserDefaults.standard.bool(forKey: "runExplicit")
    }

    // MARK: - Result of one tagger-parser prediction
    /// Everything one tagger-parser prediction produces. UPOS tags and neural lemmas are decoded
    /// ONCE, while the prediction is being processed (the lemmatiser needs the UPOS tags anyway),
    /// and stored here for the later steps to read. The remaining outputs are kept as
    /// `LogitReader`s, which have already been validated against the vocabularies.
    /// Replaces `TaggerRawOutput` for this pipeline.

    struct TaggerOutput {
        let sentence: HashableSentence
        let seqLen: Int                 // words + 1; row 0 is the synthetic ROOT
        let upos: [String]              // one per real word (rows 1..<seqLen)
        let lemmas: [String]            // lemmatiser output, one per real word
        let feats: BERTpipeHelperStructs.LogitReader          // [1, seqLen, nFeats]
        let ruleLemma: BERTpipeHelperStructs.LogitReader      // [1, seqLen, nRules]
        let arcs: BERTpipeHelperStructs.LogitReader           // [1, seqLen, seqLen]  indexed [0, dependent, head]
        let deprels: BERTpipeHelperStructs.LogitReader        // [1, nDeprels, seqLen, seqLen]  indexed [0, label, dependent, head]
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

        // [1, chars, 4]: one label per character
        let logits: BERTpipeHelperStructs.LogitReader
        do {
            logits = try BERTpipeHelperStructs.LogitReader(output, "logits", rank: 3, rows: chars.count, labels: 4)
        } catch {
            throw PipelineError.IngestionError.tokenizationFail("tokenizer output unusable: \(error)")
        }
        var tokenLists: [[String]] = []
        var currentSentence: [String] = []
        var currentWord = ""

        for (i, ch) in chars.enumerated() {
            let label = logits.argmax(row: i)
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
    /// Runs the model once, wraps every output in a validated `LogitReader`, decodes UPOS once, and runs
    /// the lemmatiser. The default processing level is 5 (everything is used), so all of this is done eagerly.
    private func runTaggerParserModel(on sentence: HashableSentence) throws -> TaggerOutput {
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
        // Validate and wrap every output once. The checks cover: output present, expected rank,
        // enough rows, a supported element type, and (where given) a label dimension that matches the vocabulary.
        // xpos_logits is not used at present, so it is not read
        let uposReader: BERTpipeHelperStructs.LogitReader
        let feats: BERTpipeHelperStructs.LogitReader
        let ruleLemma: BERTpipeHelperStructs.LogitReader
        let arcs: BERTpipeHelperStructs.LogitReader
        let deprels: BERTpipeHelperStructs.LogitReader
        do {
            uposReader = try BERTpipeHelperStructs.LogitReader(output, "upos_logits", rank: 3, rows: seqLen, labels: uposVocab.itos.count)
            feats = try BERTpipeHelperStructs.LogitReader(output, "feats_logits", rank: 3, rows: seqLen, labels: featsVocab.itos.count)
            ruleLemma = try BERTpipeHelperStructs.LogitReader(output, "lemma_rule_logits", rank: 3, rows: seqLen, labels: lemmaRuleVocab.itos.count)
            arcs = try BERTpipeHelperStructs.LogitReader(output, "arc_logits", rank: 3, rows: seqLen)
            deprels = try BERTpipeHelperStructs.LogitReader(output, "label_logits", rank: 4, rows: seqLen, labels: deprelVocab.itos.count)
        } catch {
            if runExplicit { print(describeOutputs(output)) }
            throw PipelineError.ProcessingError.predictionFailedAtLogits("unexpected model output type 310 :: \(error)")
        }

        // UPOS: decoded here,
        let upos = (1..<seqLen).map { uposVocab.decode(uposReader.argmax(row: $0)) }
        // get the lemmas with the LemmatizerRunner() as runner
        let lemmas: [String]
        do {
            let runner = self.lemmatizerRunner
            lemmas = try tokens.enumerated().map { i, form in
                try runner.lemmatize(form: form, upos: upos[i])
            }
        } catch {
            throw PipelineError.ProcessingError.lemmatizationFailed("lemmatizer failed: \(error)")
        }

        return TaggerOutput(
            sentence: sentence, seqLen: seqLen,
            upos: upos, lemmas: lemmas,
            feats: feats, ruleLemma: ruleLemma, arcs: arcs, deprels: deprels
        )
    }

    /// "name: [shape]" for every output the model produced, for diagnosing a mismatch.
    private func describeOutputs(_ output: MLFeatureProvider) -> [String] {
        output.featureNames.sorted().map { name in
            let shape = output.featureValue(for: name)?.multiArrayValue?.shape ?? []
            return "\(name): \(shape)"
        }
    }

    // MARK: XPOS (not used at present, but here to make future mods easier if it's needed)
    // To re-enable: add an `xpos: LogitReader` to TaggerOutput, build it in runTaggerParserModel, and
    //    private func decodeXPOS(_ raw: TaggerOutput) -> [String] {
    //        (1..<raw.seqLen).map { xposVocab.decode(raw.xpos.argmax(row: $0)) }
    //    }

    // MARK: Step 3 (decode) -- lemmatisation with edit-script rule
    /// 1x lemma string per real word, made by applying the predicted edit-script rule to word's raw form.
    func decodeRuleLemmas(_ raw: TaggerOutput) -> [String] {
        zip(1..<raw.seqLen, raw.sentence.tokens).map { t, form in
            applyLemmaRule(form: form, rule: lemmaRuleVocab.decode(raw.ruleLemma.argmax(row: t)))
        }
    }

    // decode rule lemmas moved to UDDecoding extension via protocol
    private func getLemmas(_ raw: TaggerOutput) -> [String] {
        let dev = false // set to true for dev test
        var returnItem: [String]
        if dev {
            returnItem = []
            for item in raw.lemmas {
                returnItem.append("dev_\(item)")
            }
        } else {
            returnItem = raw.lemmas
        }
        return returnItem
    }

    // MARK: Step 4 (decode) -- morphological features
    private func decodeFeats(_ raw: TaggerOutput) -> [String] {
        (1..<raw.seqLen).map { featsVocab.decode(raw.feats.argmax(row: $0)) }
    }

    // MARK: Step 5 (decode) -- dependency parsing via methods in protocol extension
    private func decodeDependencies(_ raw: TaggerOutput) -> [(head: Int, deprel: String)] {
        decodeParse(
            runExplicit: true,
            wordCount: raw.seqLen - 1,
            deprelVocab: deprelVocab,
            arcScore: { d, h in Double(raw.arcs.value(row: d, column: h)) },
            labelScore: { c, t, head in Double(raw.deprels.value(channel: c, row: t, column: head)) }
        )
    }

    // MARK: Per-sentence processing: for progress-reporting callers
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
                uposTags = raw.upos
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
                if level >= 4 { featsTags = decodeFeats(raw) }
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
        for (i, v) in values.enumerated() { arr[i] = NSNumber(value: v)  }
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
}
