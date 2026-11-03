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
        let taggerModel: MLModel?
        let labels: BERTpipeHelperStructs.LabelVocabs?
        var seqLen: Int?
        var maxWords: Int?
        let modelArchitecture: ModelArchitecture = myConfig.parsingConfig.modelArchitecture

        var mlcPackagePaths: MLCPackagePath
        mlcPackagePaths = await makeMlcNames(languageCode: languageCode, base: myConfig.parsingConfig.modelArchitecture, treebank: treebank)
        await onProgress(1, "Load vocabs")
        
        
        labels = try await BERTlikePipelineLoader.loadLabelVocabularies(languageCode: languageCode, treebank: treebank, modelArchitecture: modelArchitecture)
        
        await onProgress(2, "Load tokenizer")
        switch modelArchitecture {
            case .camembert, .roberta:
                guard let url = Bundle.main.url(forResource: mlcPackagePaths.tokenizerName, withExtension: "json") else {
                    throw PipelineError.GenericError.missingResource("\(mlcPackagePaths.tokenizerName).json")
                }
                tokenizer = try await SentencePieceTokenizer(tokenizerJSON: url)
                // sent piece
            case .distilbert:
                await onProgress(2, "Load wordpiece tokenizer")
                tokenizer = try await WordPieceTokenizer.fromBundle(languageCode: languageCode, treebank: treebank)
            default:
                throw PipelineError.ConfigurationError.architectureConflict
        }

        await onProgress(3, "Load bertlike model")
        taggerModel = try await BERTlikePipeline.loadMlpackage(named: mlcPackagePaths.packageName, myConfig: myConfig)
        
        await onProgress(4, "Verifying settings")
        if let tmodel = taggerModel{
            let limits = try await Self.limits(of: tmodel)
            seqLen = limits.seqLen
            maxWords = limits.maxWords
        }
        guard
            let tokenizer = tokenizer, let taggerModel = taggerModel, let labels = labels, let seqLen = seqLen, let maxWords = maxWords else { throw PipelineError.ConfigurationError.notReadyToSendToRunner }
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
    /// convert id -> label as string.

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
