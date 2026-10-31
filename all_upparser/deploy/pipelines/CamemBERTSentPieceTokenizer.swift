//
//  BertPipelineSettingsTestView.swift
//  Tagger
//
//  Created by Adam on 20/10/2026.
//

import SwiftUI
internal import UniformTypeIdentifiers
import CoreML

// MARK: - tokenizer.json (Hugging Face fast tokenizer) decoding
private struct SentencePieceTokenizerFile: Decodable {
    struct Model: Decodable {
        let type: String
        let vocab: [SentencePieceVocabEntry]
    }
    /// A vocab entry is a two-element array: ["▁le", -5.123]
    struct SentencePieceVocabEntry: Decodable {
        let piece: String
        let score: Double
        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            piece = try container.decode(String.self)
            score = try container.decode(Double.self)
        }
    }
    struct SentencePieceAddedToken: Decodable {
        let id: Int
        let special: Bool
    }
    let model: Model
    let addedTokens: [SentencePieceAddedToken]?

    enum CodingKeys: String, CodingKey {
        case model
        case addedTokens = "added_tokens"
    }
}

// MARK: - SentencePiece (Unigram) tokenizer for CamemBERT

/// Reimplements what the Hugging Face fast CamemBERT tokenizer does when it is
/// given pre-split words (`is_split_into_words=True`):
///
///   per word:  normalize (NFKC approximation) -> prepend "▁" -> Unigram/Viterbi split
///   sentence:  <s> + all pieces + </s>
///
/// Load it from the `tokenizer.json` that train_bert.py saved in the model's `tokenizer/` folder. Special-tokens
/// are read from the file, not hardcoded (for camembert-base they are <pad>=1, <unk>=3, <s>=5, </s>=6).
final class SentencePieceTokenizer: SubwordEncoder, BERTlikeTokenizerHelper {
    let padID: Int32
    let startID: Int32      // <s>, plays the role of [CLS]
    let endID: Int32        // </s>, plays the role of [SEP]
    let unkID: Int32
    var showPieces: Bool = false
    private let pieces: [String: (id: Int32, score: Double)]
    private let maxPieceLength: Int         // in Unicode scalars
    private let unkScore: Double
    private static let marker = "\u{2581}"  // "▁"
    private let idToPieces: [String]
    init(tokenizerJSON url: URL) throws {
        guard let data = try? Data(contentsOf: url) else { throw PipelineError.SentencePieceTokenizerError.fileUnreadable(url) }
        let file = try JSONDecoder().decode(SentencePieceTokenizerFile.self, from: data)
        guard file.model.type == "Unigram" else { throw PipelineError.SentencePieceTokenizerError.unsupportedModel(file.model.type) }
        let vocab = file.model.vocab

        func id(of token: String) throws -> Int32 {
            guard let index = vocab.firstIndex(where: { $0.piece == token }) else {
                throw PipelineError.SentencePieceTokenizerError.missingSpecialToken(token)
            }
            return Int32(index)
        }
        let pad = try id(of: "<pad>")
        let start = try id(of: "<s>")
        let end = try id(of: "</s>")
        let unk = try id(of: "<unk>")
        padID = pad
        startID = start
        endID = end
        unkID = unk

        // Special tokens (<s>, <pad>, <mask>, ...) must never come out of the
        // Viterbi search for ordinary text, so keep them out of the lookup table.
        var skip = Set((file.addedTokens ?? []).filter { $0.special }.map { $0.id })
        skip.formUnion([pad, start, end, unk].map { Int($0) })

        var table: [String: (id: Int32, score: Double)] = [:]
        var longest = 1
        for (index, entry) in vocab.enumerated() where !skip.contains(index) {
            if entry.piece.hasSuffix("NOTUSED") { continue }   // fairseq placeholder ids
            if table[entry.piece] == nil {
                table[entry.piece] = (Int32(index), entry.score)
            }
            longest = max(longest, entry.piece.unicodeScalars.count)
        }
        pieces = table
        idToPieces = vocab.map {$0.piece}
        maxPieceLength = longest
        // Same rule as SentencePiece/tokenizers: unknown-character score == lowest vocab score minus 10.
        unkScore = (vocab.map { $0.score }.min() ?? 0) - 10
    }

    // MARK: Encoding
    func encode(words: [String], seqLen: Int, maxWords: Int) throws -> BERTpipeEncodedSentence? {
        var ids: [Int32] = [startID]
        var wordIndex: [Int32] = [0]                       // ROOT slot points at <s>
        var pieceStrings: [[String]] = []
        
        for word in words {
            var wordIDs: [Int32] = []
            for part in normalize(word) {
                wordIDs += pieceIDs(for: part)
            }
            if wordIDs.isEmpty { wordIDs = [unkID] }       // keep word/slot alignment
            wordIndex.append(Int32(ids.count))
            ids += wordIDs
            if showPieces {
                pieceStrings.append(wordIDs.map {idToPieces[Int($0)]})
            }
        }
        ids.append(endID)

        guard ids.count <= seqLen, wordIndex.count <= maxWords else {
            throw PipelineError.SentencePieceTokenizerError.tooLong(subwords: ids.count, seqLen: seqLen,
                                         slots: wordIndex.count, maxWords: maxWords)
        }
        let length = ids.count
        ids += [Int32](repeating: padID, count: seqLen - ids.count)
        wordIndex += [Int32](repeating: -1, count: maxWords - wordIndex.count)
        return SentencePieceEncodedSentence(inputIDs: ids, wordIndex: wordIndex,
                                            wordCount: words.count, length: length, pieces: showPieces ? pieceStrings : nil)
    }

    /// Approximates SentencePiece's nmt_nfkc normalizer: NFKC, then whitespace
    /// variants -> plain space and other control characters are dropped.
    /// A word that contains whitespace after normalization splits into several
    /// parts (each gets its own "▁"), all belonging to the same word.
    private func normalize(_ word: String) -> [String] {
        var cleaned = String.UnicodeScalarView()
        for scalar in word.precomposedStringWithCompatibilityMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control:
                if scalar == "\t" || scalar == "\n" || scalar == "\r" { cleaned.append(" ") }
            case .spaceSeparator, .lineSeparator, .paragraphSeparator:
                cleaned.append(" ")
            default:
                cleaned.append(scalar)
            }
        }
        return String(cleaned).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    /// Best-scoring segmentation (Viterbi) of "▁" + part into vocabulary pieces.
    private func pieceIDs(for part: String) -> [Int32] {
        let scalars = Array((Self.marker + part).unicodeScalars)
        let n = scalars.count

        var bestScore = [Double](repeating: -.infinity, count: n + 1)
        var backLength = [Int](repeating: 0, count: n + 1)
        var backID = [Int32](repeating: unkID, count: n + 1)
        bestScore[0] = 0

        for start in 0..<n where bestScore[start] > -.infinity {
            var hasSingleScalarPiece = false
            for length in 1...min(maxPieceLength, n - start) {
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[start..<start + length])
                guard let entry = pieces[String(view)] else { continue }
                if length == 1 { hasSingleScalarPiece = true }
                let candidate = bestScore[start] + entry.score
                if candidate > bestScore[start + length] {
                    bestScore[start + length] = candidate
                    backLength[start + length] = length
                    backID[start + length] = entry.id
                }
            }
            if !hasSingleScalarPiece {                      // unknown character
                let candidate = bestScore[start] + unkScore
                if candidate > bestScore[start + 1] {
                    bestScore[start + 1] = candidate
                    backLength[start + 1] = 1
                    backID[start + 1] = unkID
                }
            }
        }

        var reversed: [Int32] = []
        var end = n
        while end > 0 {
            reversed.append(backID[end])
            end -= backLength[end]
        }
        // Consecutive unknown characters collapse into a single <unk> like HF unigram model which fuses UNKs
        var result: [Int32] = []
        for id in reversed.reversed() {
            if id == unkID, result.last == unkID { continue }
            result.append(id)
        }
        return result
    }
}

