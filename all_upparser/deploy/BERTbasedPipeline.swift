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

final class BERTlikePipelineLoader: ObservableObject, PipelineLoader{
    @Published var loadingProgress: Double = min(1.0, 0.0)
    @Published var statusMessage: String = "Waiting to load..."
    @Published var loadingComplete: Bool = false
    
    var wordPieceTokenizer: WordPieceTokenizer?
    var taggerModel: MLModel?
    var labels: LabelVocabsForBERTlike?
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
        labels: LabelVocabsForBERTlike,
        seqLen: Int,
        maxWords: Int,
        languageCode: String,
        treebank: String,
        runExplicitValue: Bool
    ) throws -> BERTlikePipeline {
        print("calling converter")
        return BERTlikePipeline(
            taggerModel: taggerModel,
            wordPieceTokenizer: wordPieceTokenizer,
            labels: labels,
            seqLen: seqLen,
            maxWords: maxWords,
            runExplicitValue: runExplicitValue
        )
    }
    
    @concurrent
    func loadBERTlikePipe(
        myConfig: TaggerConfig,
        onProgress: @MainActor @Sendable (Int, String) -> Void
    ) async throws -> BERTlikePipeline {
        let myConfig: TaggerConfig = myConfig
        let vX = "v2"
        let languageCode = myConfig.parsingConfig.selectedLanguage.rawValue
        let treebank = await myConfig.parsingConfig.selectedTreebank.short
        let runExplicitValue: Bool = myConfig.parsingConfig.runExplicit
        print("loading on main thread:", Thread.isMainThread)
        
        let wordPieceTokenizer: WordPieceTokenizer?
        let taggerModel: MLModel?
        let labels: LabelVocabsForBERTlike?
        var seqLen: Int?
        var maxWords: Int?
        // tokenizer model
        
        await onProgress(1, "Load vocabs")
        labels = try await LabelVocabsForBERTlike.loadLabelVocabularies(languageCode: languageCode, treebank: treebank, vx: vX)
        
        await onProgress(2, "Load wordpiece tokenizer")
        wordPieceTokenizer = try await WordPieceTokenizer.fromBundle(languageCode: languageCode, treebank: treebank, vx: vX)
        
        await onProgress(3, "Load tagger model")
        taggerModel = try await BERTlikePipeline.loadMlpackage(named: "\(languageCode)_distilbert_tagger_parser_\(treebank)\(vX)", myConfig: myConfig)
        
        await onProgress(4, "Verifying settings")
        
        if let tmodel = taggerModel{
            let limits = try await Self.limits(of: tmodel)
            seqLen = limits.seqLen
            maxWords = limits.maxWords
        }
        
        guard
            let wordPieceTokenizer = wordPieceTokenizer, let taggerModel = taggerModel, let labels = labels, let seqLen = seqLen, let maxWords = maxWords else { throw PipelineError.notReadyToSendToRunner }
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
    /// seqLen and maxWords are the second dimension of the two [1, N] inputs.
    private static func limits(of model: MLModel) throws -> (seqLen: Int, maxWords: Int) {
        func length(of input: String) throws -> Int {
            guard let shape = model.modelDescription.inputDescriptionsByName[input]?
                .multiArrayConstraint?.shape, shape.count == 2 else {
                throw PipelineError.invalidModelInputs("\(input) isn't a [1, N] array input")
            }
            return shape[1].intValue
        }
        let seqLen = try length(of: "input_ids")
        let maxWords = try length(of: "word_index")
        guard maxWords <= seqLen - 1 else {
            throw PipelineError.invalidModelInputs(
                "word_index length \(maxWords) must be at most input_ids length \(seqLen) - 1")
        }
        return (seqLen, maxWords)
    }
    
    /// convert id -> label as string.
    private static func label(_ vocab: Vocab, _ id: Int) -> String { vocab.decode(id) }
    
}

final class BERTlikePipeline: PipelineHelper,PipelineLoader {
    private let taggerModel: MLModel
    let labels: LabelVocabsForBERTlike
    let description: String = "BERTlikePipeline"

    /// fixed lengths the model was converted with, loaded from model for safety
    let wordPieceTokenizer: WordPieceTokenizer
    let seqLen: Int
    let maxWords: Int
    let runExplicit: Bool
    
    init(
        taggerModel: MLModel,
        wordPieceTokenizer: WordPieceTokenizer,
        labels: LabelVocabsForBERTlike,
        seqLen: Int,
        maxWords: Int,
        runExplicitValue: Bool,
    )  {
        self.taggerModel = taggerModel
        self.wordPieceTokenizer = wordPieceTokenizer
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

        var wordPieceTokenizer = self.wordPieceTokenizer                  // a copy; the vocabulary isn't duplicated
        wordPieceTokenizer.showWordPieces = myConfig.exportConfig.getsubtokens
        var currentWordpieceCount: Int = -3
        do {
            guard let encoded = try wordPieceTokenizer.encode(words: sentence.tokens, seqLen: seqLen, maxWords: maxWords
                ) else {
                return OnSentResult(sentence: sentence, resultType: .otherError, decoded: [])
            }
            currentWordpieceCount = encoded.wordPieces?.count ?? -4
            let output = try predict(encoded)
            let decoded = try decode(output, words: sentence.tokens, wordPieces: encoded.wordPieces)
            return OnSentResult(sentence: sentence,  subtokCount: currentWordpieceCount, resultType: .success, decoded: decoded)
        } catch WordPieceError.tooManySubwords {
            return OnSentResult(sentence: sentence,  subtokCount: currentWordpieceCount, resultType: .tooManySubtoks, decoded: [])
        } catch WordPieceError.tooManyWords {                              // backstop; the guard above catches this first
            return OnSentResult(sentence: sentence, resultType: .tooManyWords, decoded: [])
        } catch {
            if runExplicit { print("sentence failed: \(error.localizedDescription)") }
            return OnSentResult(sentence: sentence, resultType: .otherError, decoded: [])
        }
    }
    
    // MARK: Running the model
    private func predict(_ encoded: WordPieceEncodedSentence) throws -> MLFeatureProvider {
        let arrays = try encoded.multiArrays()
        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: arrays.inputIDs),
            "word_index": MLFeatureValue(multiArray: arrays.wordIndex),
        ])
        do {
            return try taggerModel.prediction(from: inputs)
        } catch {
            throw PipelineError.predictionFailed(error)
        }
    }
    // MARK: Decoding
    private func decode(_ output: MLFeatureProvider, words: [String],
                        wordPieces: [[String]]?) throws -> [Token] {
        /// 6 padded output tensors -> labelled tokens. Only the first (words + 1) cols mean anything, rest is PAD
        let n = words.count + 1
        let upos = try LogitReaderForBERTlike(output, "upos_logits", rank: 3, rows: n, labels: labels.upos.itos.count)
        let feats = try LogitReaderForBERTlike(output, "feats_logits", rank: 3, rows: n, labels: labels.feats.itos.count)
        let lemmaRules = try LogitReaderForBERTlike(output, "lemma_rule_logits", rank: 3, rows: n,
                                         labels: labels.lemmaRule.itos.count)
        let arc = try LogitReaderForBERTlike(output, "arc_logits", rank: 3, rows: n)
        let deprels = try LogitReaderForBERTlike(output, "label_logits", rank: 4, rows: n,
                                      labels: labels.deprel.itos.count)

        // deprel, head decoding
        let parse = decodeParse(
            runExplicit: true,
            wordCount: words.count,
            deprelVocab: labels.deprel,
            arcScore: { dependent, head in Double(arc.value(row: dependent, column: head)) },
            labelScore: { label, dependent, head in
                Double(deprels.value(channel: label, row: dependent, column: head))
            }
        )
        
        guard parse.count == words.count else {
            throw PipelineError.unexpectedOutput(
                "parse decoder returned \(parse.count) (head, deprel) pairs for \(words.count) words")
        }
        var tokens: [Token] = []
        tokens.reserveCapacity(words.count)
        for i in 1..<n {
            let form = words[i - 1]
            let rule = labels.lemmaRule.decode(lemmaRules.argmax(row: i))
            tokens.append(Token(
                tokid: i,
                form: form,
                lemma: applyLemmaRule(form: form, rule: rule),
                upos: labels.upos.decode(upos.argmax(row: i)),
                xpos: "_",
                feats: labels.feats.decode(feats.argmax(row: i)),
                head: String(parse[i - 1].head),
                deprel: parse[i - 1].deprel,
                col8: "_",
                col9: "_",
                subTokens: wordPieces?[i - 1]
            ))
            if runExplicit{
                var subels: String = "empty"
                let tidy1 = wordPieces?[i-1]
                if let success = tidy1{
                    subels = success.joined(separator: "/")
                }
                print("\(form) :: \(subels)")
            }
        }
        return tokens
    }
}
