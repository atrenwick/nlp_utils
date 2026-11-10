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

// pipelines derived from BERT-like, currently CamemBERT, roBERTa, DistilBERT
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
