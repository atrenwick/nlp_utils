//
//  SentencePieceTokenizer.swift
//  Tagger
//
//  Created by Adam on 30/10/2026.
//

import CoreML
import Foundation
import Combine
// loader and pipeline based on pipeline using SentPiece tokenizer :: loader uses switch on BertBase
class CamemBERTlikePipelineLoader: ObservableObject, PipelineLoader{
    @Published var loadingProgress: Double = min(1.0, 0.0)
    @Published var statusMessage: String = "Waiting to load..."
    @Published var loadingComplete: Bool = false
    
    var sentPieceTokenizer: SentencePieceTokenizer?
    var taggerModel: MLModel?
    var labels: BERTpipeHelperStructs.LabelVocabs?
    let description: String = "BertLike pipeline with SentencePiece tok"
    
    var seqLen: Int = 512
    var maxWords: Int = 192
    let runExplicit: Bool = true
    
    // super lightweight init
    init( ){ }
    
    func convertToRealPipeline(
        sentPieceTokenizer: SentencePieceTokenizer,
        taggerModel: MLModel,
        labels: BERTpipeHelperStructs.LabelVocabs,
        seqLen: Int,
        maxWords: Int,
        languageCode: String,
        treebank: String,
        runExplicitValue: Bool
    ) throws -> CamemBERTlikePipeline{
        print("calling converter")
        return CamemBERTlikePipeline(
            taggerModel: taggerModel,
            sentPieceTokenizer: sentPieceTokenizer,
            labels: labels,
            seqLen: seqLen,
            maxWords: maxWords,
            runExplicitValue: runExplicitValue
        )
    }
    
    @concurrent
    func loadCamemBERTlikePipeline(
        myConfig: TaggerConfig,
        onProgress: @MainActor @Sendable (Int, String) -> Void
    ) async throws -> CamemBERTlikePipeline{
        let myConfig: TaggerConfig = myConfig
        let languageCode = myConfig.parsingConfig.selectedLanguage.rawValue
        let treebank = await myConfig.parsingConfig.selectedTreebank.short
        let runExplicit: Bool = myConfig.parsingConfig.runExplicit
        print("loading on main thread::", Thread.isMainThread)
        
        let sentencePieceTokenizer: SentencePieceTokenizer?
        let taggerModel: MLModel?
        let labels: BERTpipeHelperStructs.LabelVocabs?
        var seqLen: Int?
        var maxWords: Int?
        var bertlikeBase: BERTlikeBase
        var tokenizerName: String
        var packageName: String
        
        await onProgress(1, "Load vocabs")
        switch myConfig.parsingConfig.modelArchitecture{
            case .camembert :
                bertlikeBase = BERTlikeBase.camembert
                tokenizerName = "\(languageCode)_camembert_tokenizer_\(treebank)"
                packageName = "\(languageCode)_camembert_tagger_parser_\(treebank)"
            case .roberta:
                bertlikeBase = BERTlikeBase.roberta
                tokenizerName = "\(languageCode)_roberta_tokenizer_\(treebank)"
                packageName = "\(languageCode)_roberta_tagger_parser_\(treebank)"
            default :
                throw PipelineError.ConfigurationError.architectureConflict
        }
        labels = try await CamemBERTlikePipelineLoader.loadLabelVocabularies(languageCode: languageCode, treebank: treebank,  base: bertlikeBase)
        
        await onProgress(2, "Load sentpiece tokenizer")
        guard let url = Bundle.main.url(forResource: tokenizerName, withExtension: "json") else {
            throw PipelineError.GenericError.missingResource("\(tokenizerName).json")
        }
        sentencePieceTokenizer = try await SentencePieceTokenizer(tokenizerJSON: url)

        await onProgress(3, "Load cbertlike model")
        taggerModel = try await CamemBERTlikePipelineLoader.loadMlpackage(named: packageName, myConfig: myConfig)
        
        await onProgress(4, "Verifying settings")
        if let tmodel = taggerModel{
            let limits = try await Self.limits(of: tmodel)
            seqLen = limits.seqLen
            maxWords = limits.maxWords
        }
        guard
            let sentencePieceTokenizer = sentencePieceTokenizer, let taggerModel = taggerModel, let labels = labels, let seqLen = seqLen, let maxWords = maxWords else { throw PipelineError.ConfigurationError.notReadyToSendToRunner }
        return try await convertToRealPipeline(
            sentPieceTokenizer: sentencePieceTokenizer,
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
    

final class CamemBERTlikePipeline: BERTderivedPipelineHelper, SubtokenAwarePipelineHelper, PipelineLoader {
        
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
        sentPieceTokenizer: SentencePieceTokenizer,
        labels: BERTpipeHelperStructs.LabelVocabs,
        seqLen: Int,
        maxWords: Int,
        runExplicitValue: Bool
    ){
        self.taggerModel = taggerModel
        self.tokenizer = sentPieceTokenizer
        self.labels = labels
        self.seqLen = seqLen
        self.maxWords = maxWords
        self.runExplicit = runExplicitValue
    }
}
