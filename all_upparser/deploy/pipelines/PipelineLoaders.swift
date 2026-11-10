//
//  PipelineLoaders.swift
//  Tagger
//
//  Created by Adam on 10/11/2026.
//
import Foundation
import Combine
import CoreML
import NaturalLanguage

/// Common methods for loading pipelines ::  note this protocol has no properties as conforming types have a variety of custom properties
protocol PipelineLoader { }

extension PipelineLoader{
    // loading
    /// seqLen and maxWords are the second dimension of the two [1, N] inputs.
    func makeMlcNames(languageCode: String, base: ModelArchitecture, treebank: String) -> MLCPackagePath {
        var tokName: String
        var tagParsName: String
        switch base{
            case .camembert:
                tokName = "_camembert_tokenizer_"
                tagParsName = "_camembert_tagger_parser_"
            case .distilbert:
                tokName = "_this will be ignored_"
                tagParsName = "_distilbert_tagger_parser_"
            case .cnnBiLSTM:
                tokName = "_this will be ignored_"
                tagParsName = "_this will be ignored_"
            case .rnn:
                tokName = "devWithExplicit"
                tagParsName = "devWithExplicit"
            case .roberta:
                tokName = "_roberta_tokenizer_"
                tagParsName = "_roberta_tagger_parser_"
        }
        tokName = "\(languageCode)\(tokName)\(treebank)"
        tagParsName = "\(languageCode)\(tagParsName)\(treebank)"
        return MLCPackagePath(tokenizerName: tokName, packageName: tagParsName)
    }
    
    /// get the max number of tokens == maxWords and max number of sub-tokens = seqLen for a model
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
    
    /// load UPOS, Feats, DEPREL and lemma-rule vocabs
    static func loadLabelVocabularies(languageCode: String,
                                      treebank: String,
                                      bundle: Bundle = .main,
                                      modelArchitecture: ModelArchitecture
    ) throws -> BERTpipeHelperStructs.LabelVocabs {
        
        func vocab(_ label: String) throws -> Vocab {
            let name: String
            switch modelArchitecture {
            case .distilbert:
                name = "\(languageCode)_distilbert_\(label)_vocab_\(treebank)"
            case .camembert:
                name = "\(languageCode)_camembert_\(label)_vocab_\(treebank)"
            case .roberta:
                name = "\(languageCode)_roberta_\(label)_vocab_\(treebank)"
                case .cnnBiLSTM, .rnn:
                    throw PipelineError.ConfigurationError.architectureConflict
            }
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw PipelineError.LoadingError.resourceMissing("\(name).json")
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(VocabData.self, from: data)
            return Vocab(data: decoded)
        }

        return BERTpipeHelperStructs.LabelVocabs(
            upos: try vocab("upos"),
            feats: try vocab("feats"),
            deprel: try vocab("deprel"),
            lemmaRule: try vocab("lemma_rule")
        )
    }
    /// safely load ML compiled model
    static func loadMlpackage(named name: String, myConfig: TaggerConfig) throws -> MLModel{
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            throw PipelineError.LoadingError.packageLoadFailed(name)
        }
        do {
            switch myConfig.parsingConfig.modelArchitecture {
                case .distilbert, .camembert, .roberta, .rnn:
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


/// loader for RNN pipeline
final class RNNPipelineLoader: ObservableObject, PipelineLoader{
    @Published var loadingProgress: Double = min(1.0, 0.0)
    @Published var statusMessage: String = "Waiting to load"
    @Published var loadingComplete: Bool = false
    
    //    var tokenizer: MLModel?
    var taggerModel: MLModel?
    var lemmatizerModel: MLModel?
    var modelArchitecture: ModelArchitecture?
    var seqLen: Int = 256
    var maxWords: Int = 999
    let runExplicit: Bool = true
    
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
    init( ){  }
    
    func convertToRealRNNPipe(
        taggerModel: MLModel,
        taggerMeta: RNNTaggerMeta,
        encoderModel: MLModel,
        stepModel: MLModel,
        lemmaMeta: RNNLemmatizerMeta,
        seqLen: Int,
        maxWords: Int,
        languageCode: String,
        treebank: String,
        runExplicitValue: Bool,
        tagRole: RNNTagRole,
        normalizeToNFC: Bool,
        lowercaseLemmaInput: Bool
    ) throws -> RNNPipeline {
        return try RNNPipeline(
            taggerModel: taggerModel,
            taggerMeta: taggerMeta,
            encoderModel: encoderModel,
            stepModel: stepModel,
            lemmaMeta: lemmaMeta,
            tagRole: tagRole,
            normalizeToNFC: normalizeToNFC,
            lowercaseLemmaInput: lowercaseLemmaInput,
            maxWords: maxWords,
            seqLen: 999,
            languageCode: languageCode,
            treebank: treebank,
            runExplicitValue: runExplicit,
        )
    }
    
    // MARK: Loading from a folder of compiled models
    @concurrent
    func loadRNNpipeline(
        myConfig: TaggerConfig,
        onProgress: @MainActor @Sendable (Int, String) -> Void
    ) async throws -> RNNPipeline {
        let myConfig: TaggerConfig = myConfig
        let languageCode = myConfig.parsingConfig.selectedLanguage.rawValue
        let treebank = await myConfig.parsingConfig.selectedTreebank.short
        let runExplicit: Bool = myConfig.parsingConfig.runExplicit
        let tagRole: RNNTagRole = .xpos
        let normalizeToNFC: Bool = true
        let lowercaseLemmaInput: Bool = false
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
//        guard let taggerFileName = Bundle.main.url(forResource: "\(languageCode)_rnn_vocab_rnn", withExtension: ".json" ) else {
//            throw PipelineError.LoadingError.resourceMissing("\(languageCode)_rnn_vocab_rnn.json")
//        }
        await onProgress(1, "Loading tagger data")
//        let tagMeta = try await JSONDecoder().decode(RNNTaggerMeta.self, from: Data(contentsOf: taggerFileName))
        let tagMeta: RNNTaggerMeta = try await Bundle.main.safelyDecodeJson("\(languageCode)_rnn_vocab_rnn")
        
        await onProgress(2, "Loading lemmatizer data")
//        guard let lemmatizerFileName = Bundle.main.url(forResource: "\(languageCode)_rnn_encoder_vocab_nmt", withExtension: ".json") else {
//            throw PipelineError.LoadingError.resourceMissing("\(languageCode)_rnn_encoder_vocab_nmt.json")
//        }
//        let lemMeta = try await JSONDecoder().decode(RNNLemmatizerMeta.self, from: Data(contentsOf: lemmatizerFileName))
        let lemMeta: RNNLemmatizerMeta = try await Bundle.main.safelyDecodeJson("\(languageCode)_rnn_encoder_vocab_nmt")
        
        await onProgress(3, "Loading tagger model")
        let taggerModel = try await RNNPipelineLoader.loadMlpackage(named: "\(languageCode)_rnn_model_rnn", myConfig: myConfig)
        
        await onProgress(4, "Loading lemmatizer encoder")
        let encoderModel = try await RNNPipelineLoader.loadMlpackage(named: "\(languageCode)_rnn_encoder_nmt", myConfig: myConfig)

        await onProgress(5, "Loading lemmatizer decoder")
        let decoderStepModel = try await RNNPipelineLoader.loadMlpackage(named: "\(languageCode)_rnn_decoder_step_nmt", myConfig: myConfig)
        
        return try await convertToRealRNNPipe(
            taggerModel: taggerModel,
            taggerMeta: tagMeta,
            encoderModel: encoderModel,
            stepModel: decoderStepModel,
            lemmaMeta: lemMeta,
            seqLen: 999,
            maxWords: maxWords,
            languageCode: languageCode,
            treebank: treebank,
            runExplicitValue: runExplicit,
            tagRole: tagRole,
            normalizeToNFC: normalizeToNFC,
            lowercaseLemmaInput: lowercaseLemmaInput,
        )
    }
}

// loader and pipeline based on pipeline using SentPiece tokenizer :: loader uses switch on BertBase
class BERTlikePipelineLoader: ObservableObject, PipelineLoader{
    @Published var loadingProgress: Double = min(1.0, 0.0)
    @Published var statusMessage: String = "Waiting to load..."
    @Published var loadingComplete: Bool = false

    var tokenizer: BERTlikeTokenizerHelper?
    var taggerModel: MLModel?
    var labels: BERTpipeHelperStructs.LabelVocabs?
    var modelArchitecture: ModelArchitecture?
    var seqLen: Int = 512
    var maxWords: Int = 192
    let runExplicit: Bool = true

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

        switch modelArchitecture {
            case .camembert, .roberta:
                await onProgress(2, "Loading tokenizer")
                print("camembertpipe line 94")
                guard let url = Bundle.main.url(forResource: mlcPackagePaths.tokenizerName, withExtension: "json") else {
                    print("camembertpipe line 96")
                    throw PipelineError.GenericError.missingResource("\(mlcPackagePaths.tokenizerName).json")
                }
                // Wrap in try? to catch file system errors and convert to custom error
                guard let internalTokenizer = try? await SentencePieceTokenizer(tokenizerJSON: url) else {
                    print("camembertpipeline line 101")
                    throw PipelineError.GenericError.missingResource("\(mlcPackagePaths.tokenizerName).json")
                }
                tokenizer = internalTokenizer
            case .distilbert:
                await onProgress(2, "Loading wordpiece tokenizer")
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

/// Lightweight loader for CNNBiLSTM pipeline, not designed to persist or be used for prediction
final class CNNBiLSTMPipelineLoader: ObservableObject, PipelineLoader {
    /// 1. Published properties for UI progress meter to track
    @Published var loadingProgress: Double = min(1.0, 0.0)
    @Published var statusMessage: String = "Waiting to load..."
    @Published var loadingComplete: Bool = false
    
    /// 2. The heavy properties are all optional variables, which will be populated during async loading
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
    
    /// lightweight properties
    static let rootToken = "<root>"
    static let maxWordLen = 20 // matches tagger_parser/data.py's encode_sentence default
    let maxWords: Int = 256
    private var runExplicit: Bool {
        UserDefaults.standard.bool(forKey: "runExplicit")
    }
    
    /// 3. LIGHTWEIGHT INIT
    init() {}

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
    /// actually load the pipeline elements with try + await to get optionals then guard to check all optionals have values
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

        // 1. Tokenizer Model
        await onProgress(1, "Loading tokenizer model")
        let tokName = "\(languageCode)_tokenizer_\(treebank)"
        tokenizerModel = try await safeLoad(name: "\(tokName).mlc") {
            try await Self.loadMlpackage(named: tokName, myConfig: myConfig)
        }

        // 2. Tagger Model
        await onProgress(2, "Loading tagger")
        let tagName = "\(languageCode)_tagger_parser_\(treebank)"
        taggerModel = try await safeLoad(name: "\(tagName).mlc") {
            try await Self.loadMlpackage(named: tagName, myConfig: myConfig)
        }

        // 3-9. Vocabularies with safeLoad for each to ensure we know WHICH vocab failed
        await onProgress(3, "Loading tokenizer char vocab")
        tokenizerCharVocab = try await safeLoad(name: "\(languageCode)_tokenizer_char_vocab_\(treebank)") {
            try await Vocab.load(named: "\(languageCode)_tokenizer_char_vocab_\(treebank)")
        }

        await onProgress(4, "Loading word vocab")
        wordVocab = try await safeLoad(name: "\(languageCode)_word_vocab_\(treebank)") {
            try await Vocab.load(named: "\(languageCode)_word_vocab_\(treebank)")
        }

        await onProgress(5, "Loading tagger char vocab")
        taggerCharVocab = try await safeLoad(name: "\(languageCode)_tagger_char_vocab_\(treebank)") {
            try await Vocab.load(named: "\(languageCode)_tagger_char_vocab_\(treebank)")
        }

        await onProgress(6, "Loading upos vocab")
        uposVocab = try await safeLoad(name: "\(languageCode)_upos_vocab_\(treebank)") {
            try await Vocab.load(named: "\(languageCode)_upos_vocab_\(treebank)")
        }

        await onProgress(7, "Loading feats vocab")
        featsVocab = try await safeLoad(name: "\(languageCode)_feats_vocab_\(treebank)") {
            try await Vocab.load(named: "\(languageCode)_feats_vocab_\(treebank)")
        }

        await onProgress(8, "Loading deprel vocab")
        deprelVocab = try await safeLoad(name: "\(languageCode)_deprel_vocab_\(treebank)") {
            try await Vocab.load(named: "\(languageCode)_deprel_vocab_\(treebank)")
        }

        await onProgress(9, "Loading lemma rule vocab")
        lemmaRuleVocab = try await safeLoad(name: "\(languageCode)_lemma_rule_vocab_\(treebank)") {
            try await Vocab.load(named: "\(languageCode)_lemma_rule_vocab_\(treebank)")
        }

        // 10. Lemmatizer runner
        await onProgress(10, "Loading neural lemmatizer")
        lemmatizerRunner = try await LemmatizerRunner(languageCode: languageCode, treebank: treebank)

        // guard to check all values actually exist and pass them to the converter, which only takes non-optionals
        guard let tokenizerModel = tokenizerModel, let taggerModel = taggerModel,
              let lemmatizerRunner = lemmatizerRunner, let tokenizerCharVocab = tokenizerCharVocab,
              let wordVocab = wordVocab, let taggerCharVocab = taggerCharVocab,
              let uposVocab = uposVocab, let featsVocab = featsVocab,
              let deprelVocab = deprelVocab, let lemmaRuleVocab = lemmaRuleVocab else {
            await onProgress(0, "Error")
            print("cnnbi-error 121")
            throw PipelineError.ConfigurationError.notReadyToSendToRunner
        }

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
    /// Helper to wrap loading calls. If system error is thrown, it fets caught and custom .missingResource error instead.
    private func safeLoad<T>(
        name: String,
        loader: () async throws -> T
    ) async throws -> T {
        do {
            return try await loader()
        } catch let loadingError as PipelineError.LoadingError {
            // If it's already our custom error, just re-throw it
            throw loadingError
        } catch {
            // It's a system error (File Not Found, etc.), wrap it in our specific error
            throw PipelineError.GenericError.missingResource(name)
        }
    }
}
