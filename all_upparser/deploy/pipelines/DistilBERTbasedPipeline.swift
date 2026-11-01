//
//  BERTbasedPipeline.swift
//  Tagger
//
//  Created by Adam on 18/10/2026.
//

import Foundation
import CoreML
import SwiftUI
import Combine

class DistilBERTlikePipelineLoader: ObservableObject, PipelineLoader {
    @Published var loadingProgress: Double = min(1.0, 0.0)
    @Published var statusMessage: String = "Waiting to load..."
    @Published var loadingComplete: Bool = false
    
    var wordPieceTokenizer: WordPieceTokenizer?
    var taggerModel: MLModel?
    var labels: BERTpipeHelperStructs.LabelVocabs?
    let description: String = "BERTlikePipeline"
    
    /// fixed lengths the model was converted with, loaded from model for safety
    var seqLen: Int = 512
    var maxWords: Int = 192
    let runExplicit: Bool = true
    
    // super lightweight init
    init(){
    }
    
    func convertToRealPipeline(
        wordPieceTokenizer: WordPieceTokenizer,
        taggerModel: MLModel,
        labels: BERTpipeHelperStructs.LabelVocabs,
        seqLen: Int,
        maxWords: Int,
        languageCode: String,
        treebank: String,
        runExplicitValue: Bool
    ) throws -> DistilBERTlikePipeline {
        print("calling converter")
        return DistilBERTlikePipeline(
            taggerModel: taggerModel,
            tokenizer: wordPieceTokenizer,
            labels: labels,
            seqLen: seqLen,
            maxWords: maxWords,
            runExplicitValue: runExplicitValue
        )
    }
    
    @concurrent
    func loadDistilBERTlikePipe(
        myConfig: TaggerConfig,
        onProgress: @MainActor @Sendable (Int, String) -> Void
    ) async throws -> DistilBERTlikePipeline {
        let myConfig: TaggerConfig = myConfig
        let languageCode = myConfig.parsingConfig.selectedLanguage.rawValue
        let treebank = await myConfig.parsingConfig.selectedTreebank.short
        let runExplicitValue: Bool = myConfig.parsingConfig.runExplicit
        print("loading on main thread:", Thread.isMainThread)
        
        let wordPieceTokenizer: WordPieceTokenizer?
        let taggerModel: MLModel?
        let labels: BERTpipeHelperStructs.LabelVocabs?
        var seqLen: Int?
        var maxWords: Int?
        // tokenizer model
        
        await onProgress(1, "Load vocabs")
        labels = try await DistilBERTlikePipelineLoader.loadLabelVocabularies(languageCode: languageCode, treebank: treebank,  base: BERTlikeBase.distilbert)
        
        await onProgress(2, "Load wordpiece tokenizer")
        wordPieceTokenizer = try await WordPieceTokenizer.fromBundle(languageCode: languageCode, treebank: treebank)
        
        await onProgress(3, "Load DIS tagger model")
        taggerModel = try await DistilBERTlikePipeline.loadMlpackage(named: "\(languageCode)_distilbert_tagger_parser_\(treebank)", myConfig: myConfig)
        
        await onProgress(4, "Verifying settings")
        
        if let tmodel = taggerModel{
            let limits = try await Self.limits(of: tmodel)
            seqLen = limits.seqLen
            maxWords = limits.maxWords
        }
        
        guard
            let wordPieceTokenizer = wordPieceTokenizer, let taggerModel = taggerModel, let labels = labels, let seqLen = seqLen, let maxWords = maxWords else { throw PipelineError.ConfigurationError.notReadyToSendToRunner }
        return try await convertToRealPipeline(
            wordPieceTokenizer: wordPieceTokenizer,
            taggerModel: taggerModel,
            labels: labels,
            seqLen: seqLen,
            maxWords: maxWords,
            languageCode: languageCode,
            treebank: treebank,
            runExplicitValue: runExplicitValue
        )
    }
    /// convert id -> label as string.
    private static func label(_ vocab: Vocab, _ id: Int) -> String { vocab.decode(id) }
}

final class DistilBERTlikePipeline: BERTderivedPipelineHelper, SubtokenAwarePipelineHelper,PipelineLoader {
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
        tokenizer: WordPieceTokenizer,
        labels: BERTpipeHelperStructs.LabelVocabs,
        seqLen: Int,
        maxWords: Int,
        runExplicitValue: Bool,
    )  {
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

