//
//  SentencePieceTokenizer.swift
//  Tagger
//
//  Created by Adam on 30/10/2026.
//

import CoreML
import Foundation
import Combine
//import SwiftUI
// loader and pipeline based on pipeline using SentPiece tokenizer :: loader uses switch on BertBase
class BERTlikePipelineLoader: ObservableObject, PipelineLoader{
    @Published var loadingProgress: Double = min(1.0, 0.0)
    @Published var statusMessage: String = "Waiting to load..."
    @Published var loadingComplete: Bool = false

    var tokenizer: BERTlikeTokenizerHelper?
    var taggerModel: MLModel?
    var labels: BERTpipeHelperStructs.LabelVocabs?
    var modelArchitecture: ModelArchitecture?

    var description: String {
        switch modelArchitecture {
            case .distilbert:
                "DistilBERT based pipeline with WordPiece tokenizer"
            case .rnn:
                "RNNTagger inspired pipeline for POS, LEM"
            case .roberta:
                "XLM-roBERTa based pipeline with SentPiece tokenizer"
            case .camembert:
                "CamemBERT based pipeline with SentPiece tokenizer"
            case .cnnBiLSTM:
                 "architectureConflict"
            default:
                "Undetermined as yet, as coming from optional"
        }
    }
    
    var seqLen: Int = 512
    var maxWords: Int = 192
    let runExplicit: Bool = true
    
    // super lightweight init
    init( ){ }
    
    func convertToRealPipeline(
        tokenizer: BERTlikeTokenizerHelper,
        taggerModel: MLModel,
        labels: BERTpipeHelperStructs.LabelVocabs,
        seqLen: Int,
        maxWords: Int,
        languageCode: String,
        treebank: String,
        runExplicitValue: Bool
    ) throws -> BERTlikePipeline{
        print("calling converter")
        return BERTlikePipeline(
            taggerModel: taggerModel,
            tokenizer: tokenizer,
            labels: labels,
            seqLen: seqLen,
            maxWords: maxWords,
            runExplicitValue: runExplicitValue
        )
    }
    
    @concurrent
    func loadBERTlikePipeline(
        myConfig: TaggerConfig,
        onProgress: @MainActor @Sendable (Int, String) -> Void
    ) async throws -> BERTlikePipeline{
        let myConfig: TaggerConfig = myConfig
        let languageCode = myConfig.parsingConfig.selectedLanguage.rawValue
        let treebank = await myConfig.parsingConfig.selectedTreebank.short
        let runExplicit: Bool = myConfig.parsingConfig.runExplicit
        print("loading on main thread::", Thread.isMainThread)
        
        let tokenizer: BERTlikeTokenizerHelper?
        let labels: BERTpipeHelperStructs.LabelVocabs?
        var seqLen: Int?
        var maxWords: Int?
        let modelArchitecture: ModelArchitecture = myConfig.parsingConfig.modelArchitecture

        var mlcPackagePaths: MLCPackagePath
        mlcPackagePaths = await makeMlcNames(languageCode: languageCode, base: myConfig.parsingConfig.modelArchitecture, treebank: treebank)
        await onProgress(1, "Loading vocabs")
        
        labels = try await BERTlikePipelineLoader.loadLabelVocabularies(languageCode: languageCode, treebank: treebank, modelArchitecture: modelArchitecture)
        
        await onProgress(2, "Loading tokenizer")

        //new
        switch modelArchitecture {
            case .camembert, .roberta:
                print("camembertpipe line 94")
                guard let url = Bundle.main.url(forResource: mlcPackagePaths.tokenizerName, withExtension: "json") else {
                    print("camembertpipe line 96")
                    throw PipelineError.GenericError.missingResource("\(mlcPackagePaths.tokenizerName).json")
                }
                // Wrap in try? to catch file system errors and convert to your custom error
                guard let internalTokenizer = try? await SentencePieceTokenizer(tokenizerJSON: url) else {
                    print("camembertpipeline line 101")
                    throw PipelineError.GenericError.missingResource("\(mlcPackagePaths.tokenizerName).json")
                }
                tokenizer = internalTokenizer
                // sent piece
            case .distilbert:
                await onProgress(2, "Loading wordpiece tokenizer")
                // Wrap in try? here too
                guard let internalTokenizer = try? await WordPieceTokenizer.fromBundle(languageCode: languageCode, treebank: treebank) else {
                    print("camembertpipeline line 110")
                    throw PipelineError.GenericError.missingResource("WordPiece tokenizer files missing.")
                }
                tokenizer = internalTokenizer
            default:
                throw PipelineError.ConfigurationError.architectureConflict
        }

        await onProgress(3, "Loading bertlike model")
        let taggerModel = try await BERTlikePipeline.loadMlpackage(named: mlcPackagePaths.packageName, myConfig: myConfig)
        // other cases like this need to be de-guarded to keep the original error thrown from the Method
//        guard let taggerModel = try? await BERTlikePipeline.loadMlpackage(named: mlcPackagePaths.packageName, myConfig: myConfig) else {
//                print("camembertpipeline line 118")
//                throw PipelineError.GenericError.missingResource("\(mlcPackagePaths.packageName).mlc")
//        }
        //        taggerModel = try await BERTlikePipeline.loadMlpackage(named: T##String, myConfig: myConfig)
        await onProgress(4, "Verifying settings")
            let limits = try await Self.limits(of: taggerModel)
            seqLen = limits.seqLen
            maxWords = limits.maxWords
        
        guard
            
            let tokenizer = tokenizer, let labels = labels, let seqLen = seqLen, let maxWords = maxWords else {
            await onProgress(0, "Error")
            print("bert-error 117")
            throw PipelineError.ConfigurationError.notReadyToSendToRunner
        }
        return try await convertToRealPipeline(
            tokenizer: tokenizer,
            taggerModel: taggerModel,
            labels: labels,
            seqLen: seqLen,
            maxWords: maxWords,
            languageCode: languageCode,
            treebank: treebank,
            runExplicitValue: runExplicit
        )
    }
}

final class BERTlikePipeline: BERTderivedPipelineHelper, SubtokenAwarePipelineHelper, PipelineLoader {
        
    internal let taggerModel: MLModel
    let labels: BERTpipeHelperStructs.LabelVocabs
    let description: String = "BERTlikePipeline"

    /// fixed lengths the model was converted with, loaded from model for safety
    let tokenizer: any BERTlikeTokenizerHelper
    let seqLen: Int
    let maxWords: Int
    let runExplicit: Bool

    init(
        taggerModel: MLModel,
        tokenizer: BERTlikeTokenizerHelper,
        labels: BERTpipeHelperStructs.LabelVocabs,
        seqLen: Int,
        maxWords: Int,
        runExplicitValue: Bool
    ){
        self.taggerModel = taggerModel
        self.tokenizer = tokenizer
        self.labels = labels
        self.seqLen = seqLen
        self.maxWords = maxWords
        self.runExplicit = runExplicitValue
    }
    func runOnSentence(_ sentence: HashableSentence, myConfig: TaggerConfig) -> OnSentResult {
        if runExplicit { print("running on sents with bert pipeline") }

        guard !sentence.tokens.isEmpty else {
            return OnSentResult(sentence: sentence, resultType: .empty, decoded: [])
        }
        // maxWords counts the ROOT slot, so the most real words allowed is maxWords - 1
        guard sentence.tokens.count < maxWords else {
            return OnSentResult(sentence: sentence, resultType: .tooManyWords, decoded: [])
        }

        var wordPieceTokenizer = self.tokenizer                  // a copy; the vocabulary isn't duplicated
        wordPieceTokenizer.showPieces = myConfig.exportConfig.getsubtokens
        var currentWordpieceCount: Int = -3
        do {
            guard let encoded = try wordPieceTokenizer.encode(words: sentence.tokens, seqLen: seqLen, maxWords: maxWords
                ) else {
                return OnSentResult(sentence: sentence, resultType: .otherError, decoded: [])
            }
            currentWordpieceCount = encoded.pieces?.count ?? -4
            let output = try predict(encoded)
            let decoded = try decode(output, words: sentence.tokens, pieces: encoded.pieces)
            return OnSentResult(sentence: sentence,  subtokCount: currentWordpieceCount, resultType: .success, decoded: decoded)
        } catch PipelineError.TokPieceError.tooManySubwords {
            return OnSentResult(sentence: sentence,  subtokCount: currentWordpieceCount, resultType: .tooManySubtoks, decoded: [])
        } catch PipelineError.TokPieceError.tooManyWords {                              // backstop; the guard above catches this first
            return OnSentResult(sentence: sentence, resultType: .tooManyWords, decoded: [])
        } catch {
            if runExplicit { print("sentence failed: \(error.localizedDescription)") }
            return OnSentResult(sentence: sentence, resultType: .otherError, decoded: [])
        }
    }
}


final class CNNBiLSTMPipeline: PipelineHelper, LinguisticProcessingHelper, ObservableObject {
    // no change
    var seqLen: Int = 256

    // the actual pipeline for processing, with no optionals
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

    // no change
    // lightweight properties
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
    // change- addition
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
    // no change
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
//CHANGED:
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
            let label = logits.argmax(row: i) // <<<<<<---- CHANGED
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
        //// identical up to here in this function
        // Validate and wrap every output once. The checks cover: output present, expected rank,
        // enough rows, a supported element type, and (where given) a label dimension that matches the vocabulary.
        // xpos_logits is not used at present, so it is neither required nor read (see the commented decodeXPOS below).
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

        // UPOS: decoded here, ONCE. The lemmatiser needs it now, and runOnSentence reads it from the result later.
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
        ) // <<<<<<<<<<--------------------  CHANGED this return :: used to give mix of data, logits
    }

    /// "name: [shape]" for every output the model produced, for diagnosing a mismatch.
    private func describeOutputs(_ output: MLFeatureProvider) -> [String] {
        output.featureNames.sorted().map { name in
            let shape = output.featureValue(for: name)?.multiArrayValue?.shape ?? []
            return "\(name): \(shape)"
        }
    }

    // MARK: Step 2 (decode) -- UPOS
    // Nothing to do here: UPOS is decoded once in runTaggerParserModel and read from `TaggerOutput.upos`.

    // MARK: XPOS (not used at present, but here to make future mods easier if it's needed)
    // To re-enable: add an `xpos: LogitReader` to TaggerOutput, build it in runTaggerParserModel, and
    //    private func decodeXPOS(_ raw: TaggerOutput) -> [String] {
    //        (1..<raw.seqLen).map { xposVocab.decode(raw.xpos.argmax(row: $0)) }
    //    }

    // MARK: Step 3 (decode) -- lemmatisation with edit-script rule
    /// 1x lemma string per real word, made by applying the predicted edit-script rule to word's raw form.
    func decodeRuleLemmas(_ raw: TaggerOutput) -> [String] {
        zip(1..<raw.seqLen, raw.sentence.tokens).map { t, form in
            applyLemmaRule(form: form, rule: lemmaRuleVocab.decode(raw.ruleLemma.argmax(row: t)))// <<<<<<<<<<<--------------------  CHANGED
        }
    }

    // decode rule lemmas moved to UDDecoding extension via protocol
    private func getLemmas(_ raw: TaggerOutput) -> [String] {
        // set to true for dev test
        let dev = false
        var returnItem: [String]
        if dev {
            returnItem = []
            for item in raw.lemmas {
                returnItem.append("dev_\(item)")//              <<<<<<<<<<<--------------------  CHANGED
            }
        }
        else {
            returnItem = raw.lemmas//              <<<<<<<<<<<--------------------  CHANGED
        }
        return returnItem
    }

    // MARK: Step 4 (decode) -- morphological features
    private func decodeFeats(_ raw: TaggerOutput) -> [String] {
        (1..<raw.seqLen).map { featsVocab.decode(raw.feats.argmax(row: $0)) }//              <<<<<<<<<<<--------------------  CHANGED
    }

    // MARK: Step 5 (decode) -- dependency parsing
    // now in extension via protocol
    private func decodeDependencies(_ raw: TaggerOutput) -> [(head: Int, deprel: String)] {
        decodeParse(
            runExplicit: true,
            wordCount: raw.seqLen - 1,
            deprelVocab: deprelVocab,
            arcScore: { d, h in Double(raw.arcs.value(row: d, column: h)) },//              <<<<<<<<<<<--------------------  CHANGED
            labelScore: { c, t, head in Double(raw.deprels.value(channel: c, row: t, column: head)) } //<<<<<<<<<<<--------- CHANGED
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
                uposTags = raw.upos                 // already decoded: no second pass <<<<<<<<<<---- changed
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
    // no change
    func makeIntArray(_ values: [Int32], shape: [NSNumber]) throws -> MLMultiArray {
        let arr = try MLMultiArray(shape: shape, dataType: .int32)
        for (i, v) in values.enumerated() {
            arr[i] = NSNumber(value: v)
        }
        return arr
    }
    // no change
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
