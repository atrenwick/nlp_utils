//
//  BERTbasedPipeline.swift
//  Tagger
//
//  Created by Adam on 18/10/2026.
//

import Foundation
import CoreML
import SwiftUI
// MARK: - Label vocabularies

/// The five vocabularies that turn output indices back into labels. They must come from
/// the same training run as the model (train_bert.py writes them next to it); the old
/// BiLSTM vocabularies number the labels differently.
struct LabelVocabularies {
    let upos: Vocab
    let feats: Vocab
    let deprel: Vocab
    let lemmaRule: Vocab
    
    static func loadLabelVocabularies(languageCode: String,
                                      treebank: String,
                                      bundle: Bundle = .main
    ) throws -> LabelVocabularies {
        
        func vocab(_ label: String) throws -> Vocab {
            let name = "\(languageCode)_bert_\(label)_vocab_\(treebank)"
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw UDPipelineError.missingResource("\(name).json")
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(VocabData.self, from: data)
            return Vocab(data: decoded)
        }

        return LabelVocabularies(
            upos: try vocab("upos"),
            feats: try vocab("feats"),
            deprel: try vocab("deprel"),
            lemmaRule: try vocab("lemma_rule")
        )
    }
}

extension UDPipelineBERTbased {
    static func load(languageCode: String, treebank: String) async throws -> UDPipelineBERTbased {
        try await Task.detached(priority: .userInitiated) {
            try await UDPipelineBERTbased(languageCode: languageCode, treebank: treebank)
        }.value
    }
}
final class UDPipelineBERTbased{
    let wordPieceTokenizer: WordPieceTokenizer
    private let taggerModel: MLModel
    private let labels: LabelVocabularies

    /// fixed lengths the model was converted with, loaded from model for safety
    let seqLen: Int
    let maxWords: Int

    /// Designated init: takes already-loaded pieces, which also makes it easy to test.
    init(taggerModel: MLModel, wordPieceTokenizer: WordPieceTokenizer, labels: LabelVocabularies, languageCode: String, treebank: String) throws {
        let limits = try UDPipelineBERTbased.limits(of: taggerModel)
        self.taggerModel = taggerModel
        self.wordPieceTokenizer = wordPieceTokenizer
        self.labels = labels
        self.seqLen = limits.seqLen
        self.maxWords = limits.maxWords
    }

    /// Loads everything for one language/treebank. Building the tokenizer reads a ~100k-entry
    /// vocabulary, so call this off the main thread (for example inside Task.detached).
    convenience init(languageCode: String, treebank: String) throws {
        let model = try UDPipelineBERTbased.loadModel(named: "\(languageCode)_distilbert_tagger_parser_\(treebank)")
        let tokenizer = try WordPieceTokenizer.fromBundle(languageCode: languageCode,
                                                          treebank: treebank)
        let labels = try LabelVocabularies.loadLabelVocabularies(languageCode: languageCode, treebank: treebank)
        try self.init(taggerModel: model, wordPieceTokenizer: tokenizer, labels: labels, languageCode:  languageCode, treebank: treebank)
    }

    private static func loadModel(named name: String) throws -> MLModel {
        // Xcode compiles a bundled .mlpackage into a .mlmodelc at build
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            throw UDPipelineError.modelLoadFailed(name)
        }
        let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            do {
                return try MLModel(contentsOf: url, configuration: configuration)
            } catch {
                throw UDPipelineError.modelLoadFailed("load failed")
            }
        }
    /// seqLen and maxWords are the second dimension of the two [1, N] inputs.
    private static func limits(of model: MLModel) throws -> (seqLen: Int, maxWords: Int) {
        func length(of input: String) throws -> Int {
            guard let shape = model.modelDescription.inputDescriptionsByName[input]?
                    .multiArrayConstraint?.shape, shape.count == 2 else {
                throw UDPipelineError.invalidModelInputs("\(input) isn't a [1, N] array input")
            }
            return shape[1].intValue
        }
        let seqLen = try length(of: "input_ids")
        let maxWords = try length(of: "word_index")
        guard maxWords <= seqLen - 1 else {
            throw UDPipelineError.invalidModelInputs(
                "word_index length \(maxWords) must be at most input_ids length \(seqLen) - 1")
        }
        return (seqLen, maxWords)
    }
    //    // Entry points
    //    func annotate(words: [String], showWordPieces: Bool = false) async throws -> AnnotatedSentence
    //    func annotate(text: String, showWordPieces: Bool = false) async throws -> [AnnotatedSentence]
    //        // only if you keep a segmenter in front
    //
    //    // Steps inside annotate(words:)
    //    private func runModel(_ encoded: EncodedSentence) throws -> BertTaggerParserOutput
    //    private func decode(_ output: BertTaggerParserOutput, words: [String],
    //                        encoded: EncodedSentence) throws -> AnnotatedSentence
    //
    //    // Reading MLMultiArrays (honour dataType and strides; outputs are fp16 and may be padded)
    //    private func readMatrix(_ array: MLMultiArray, rows: Int, columns: Int) -> [[Float]]
    //    private func argmaxPerRow(_ matrix: [[Float]]) -> [Int]
    //    private func labelScores(from array: MLMultiArray, heads: [Int], n: Int) -> [[Float]]
    //        // label logits at each word's predicted head: [dependent][deprel]
    //}


}


//
//    //-- sketch
//// MARK: - Results
//
//struct AnnotatedToken: Identifiable, Sendable {
//    let id: Int                  // 1-based position in the sentence
//    let form: String
//    let lemma: String
//    let upos: String
//    let xpos: String
//    let feats: String            // "Case=Nom|Number=Sing", or "_"
//    let head: Int                // 0 = root
//    let deprel: String
//    let wordPieces: [String]?    // only filled when showWordPieces is on
//}
//
//struct AnnotatedSentence: Sendable {
//    let tokens: [AnnotatedToken]
//    var conllu: String
//    // optional export
//}
//
//

//// MARK: - Pure decoding helpers (no Core ML, easy to unit test)
//
//enum LemmaRule {
//    /// Mirror of data.py's apply_lemma_rule.
//    static func apply(_ rule: String, to form: String) -> String
//}
//
//enum DependencyDecoder {
//    /// arcScores[dependent][head]; index 0 is ROOT; n = words + 1.
//    /// Chu-Liu-Edmonds, so the result is a valid tree (no cycles).
//    /// Returns the head index for each dependent (entry 0 unused).
//    static func decodeHeads(arcScores: [[Float]]) -> [Int]
//}
//


