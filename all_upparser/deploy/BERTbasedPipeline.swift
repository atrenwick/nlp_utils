//
//  BERTbasedPipeline.swift
//  Tagger
//
//  Created by Adam on 18/10/2026.
//

import Foundation
import CoreML
import SwiftUI


final class BERTlikePipeline: PipelineHelper, NLPPipeline{
    var wordPieceTokenizer: WordPieceTokenizer
    private let taggerModel: MLModel
    let labels: LabelVocabsForBERTlike

    /// fixed lengths the model was converted with, loaded from model for safety
    let seqLen: Int
    let maxWords: Int
    let runExplicit = true
    /// Designated init: takes already-loaded pieces, which also makes it easy to test.
    init(taggerModel: MLModel, wordPieceTokenizer: WordPieceTokenizer, labels: LabelVocabsForBERTlike, languageCode: String, treebank: String) throws {
        let limits = try BERTlikePipeline.limits(of: taggerModel)
        self.taggerModel = taggerModel
        self.wordPieceTokenizer = wordPieceTokenizer
        self.labels = labels
        self.seqLen = limits.seqLen
        self.maxWords = limits.maxWords
    }

    /// Loads everything for one language/treebank. Building the tokenizer reads a ~100k-entry
    /// vocabulary, so call this off the main thread (for example inside Task.detached).
    convenience init(myConfig: TaggerConfig) throws {
        let languageCode: String = myConfig.parsingConfig.selectedLanguage.rawValue
        let treebank: String = myConfig.parsingConfig.selectedTreebank.short
        
        let model = try BERTlikePipeline.loadMlpackage(named: "\(languageCode)_distilbert_tagger_parser_\(treebank)", myConfig: myConfig)
        let wordPieceTokenizer = try WordPieceTokenizer.fromBundle(languageCode: languageCode,
                                                          treebank: treebank)
        let labels = try LabelVocabsForBERTlike.loadLabelVocabularies(languageCode: languageCode, treebank: treebank)
        try self.init(taggerModel: model, wordPieceTokenizer: wordPieceTokenizer, labels: labels, languageCode:  languageCode, treebank: treebank)
    }

    static func load(myConfig: TaggerConfig) async throws -> BERTlikePipeline {
        /// this static func was in its own extension tot he class
        try await Task.detached(priority: .userInitiated) {
            try await BERTlikePipeline(myConfig: myConfig)
        }.value
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

    /// id -> label string. One line to adapt to your Vocab class.
    // this method was in an extension1 to UDPipelineBERTBased - annotating+decoding
    private static func label(_ vocab: Vocab, _ id: Int) -> String {
        vocab.decode(id)
    }

    /// Annotates one sentence. Runs the model synchronously (tens of milliseconds), so call it
    /// from a background task, not from the main thread.
    ///
    /// Throws PipelineError.emptyInput, WordPieceError.tooManyWords / .tooManySubwords when the
    /// sentence doesn't fit the model's fixed size, or a PipelineError for model problems.
    func runOnSentence(_ sentence: HashableSentence, myConfig: TaggerConfig) throws -> [Token] {
        print("running on sents with bert pipeline")
        guard !sentence.tokens.isEmpty else { throw PipelineError.emptyInput }
        
        var wordPieceTokenizer = self.wordPieceTokenizer                  // a copy; the vocabulary isn't duplicated
        wordPieceTokenizer.showWordPieces = myConfig.exportConfig.getsubtokens // default set to true for the moment
        
        let encoded = try wordPieceTokenizer.encode(words: sentence.tokens, seqLen: seqLen, maxWords: maxWords)
        
        let output = try predict(encoded)
        return try decode(output, words: sentence.tokens, wordPieces: encoded.wordPieces)
    }

    // MARK: Running the model
    private func predict(_ encoded: WordPieceEncodedSentence) throws -> MLFeatureProvider {
        // this method was in an extension1 to UDPipelineBERTBased - annotating+decoding
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
        /// Turns the six padded output tensors into labelled tokens. Only the first words + 1
        /// rows/columns mean anything (row 0 is the ROOT slot); the rest is padding.
        let n = words.count + 1
        
        let upos = try LogitReaderForBERTlike(output, "upos_logits", rank: 3, rows: n, labels: labels.upos.itos.count)
        let feats = try LogitReaderForBERTlike(output, "feats_logits", rank: 3, rows: n, labels: labels.feats.itos.count)
        let lemmaRules = try LogitReaderForBERTlike(output, "lemma_rule_logits", rank: 3, rows: n,
                                         labels: labels.lemmaRule.itos.count)
        let arc = try LogitReaderForBERTlike(output, "arc_logits", rank: 3, rows: n)
        let deprels = try LogitReaderForBERTlike(output, "label_logits", rank: 4, rows: n,
                                      labels: labels.deprel.itos.count)

        // Shared Chu-Liu-Edmonds decoder (UDDecoding): one (head, deprel) per word.
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
        }
        return tokens
    }
}
