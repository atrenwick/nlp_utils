//
//  SentencePieceTokenizer.swift
//  Tagger
//
//  Created by Adam on 30/10/2026.
//

import CoreML
import Foundation
import Combine

struct SentencePieceEncodedSentence: BERTpipeEncodedSentence {
    let inputIDs: [Int32]       // length seqLen
    let wordIndex: [Int32]      // length maxWords
    let wordCount: Int          // real words, without the ROOT slot
    let length: Int             // real tokens in inputIDs, including <s> and </s>
    let pieces: [[String]]?
    /// Rows/columns of each model output that are meaningful (words + ROOT).
    var validSlots: Int { wordCount + 1 }
}

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
        
        await onProgress(1, "Load vocabs")
        labels = try await CamemBERTlikePipelineLoader.loadLabelVocabularies(languageCode: languageCode, treebank: treebank,  base: BERTlikeBase.camembert)
        
        await onProgress(2, "Load sentpiece tokenizer")
        let name = "\(languageCode)_camembert_tokenizer_\(treebank)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            
            throw PipelineError.GenericError.missingResource("\(name).json")
        }
        sentencePieceTokenizer = try await SentencePieceTokenizer(tokenizerJSON: url) // .fromBundle(languageCode: languageCode, treebank: treebank, vx: vX)

        await onProgress(3, "Load tagger model")
        taggerModel = try await CamemBERTlikePipelineLoader.loadMlpackage(named: "\(languageCode)_camembert_tagger_parser_\(treebank)", myConfig: myConfig)
        
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
    let description: String = "BERTlikePipeline with sent piece tokenizer"
    
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
