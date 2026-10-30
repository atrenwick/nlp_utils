//
//  SentencePieceTokenizer.swift
//  Tagger
//
//  Created by Adam on 30/10/2026.
//

import CoreML
import Foundation
import Combine

// MARK: - Shared contract (what the Core ML model needs, whichever tokenizer made it)

/// Fixed-length inputs for the converted model.
///   input_ids  [1, seqLen]    <s> + subwords of every word + </s>, padded with `padID`
///   word_index [1, maxWords]  slot 0 = ROOT -> position 0 (<s>); slot k = position of
///                             word k's first subword; padded with -1
struct SentencePieceEncodedSentence {
    let inputIDs: [Int32]       // length seqLen
    let wordIndex: [Int32]      // length maxWords
    let wordCount: Int          // real words, without the ROOT slot
    let length: Int             // real tokens in inputIDs, including <s> and </s>
    let sentPieces: [[String]]?
    /// Rows/columns of each model output that are meaningful (words + ROOT).
    var validSlots: Int { wordCount + 1 }
}

/// Implemented by the existing WordPiece tokenizer (via a small adapter) and by
/// SentencePieceTokenizer, so the export/prediction code doesn't care which one it has.
protocol SubwordEncoder {
    func encode(words: [String], seqLen: Int, maxWords: Int) throws -> SentencePieceEncodedSentence
}

enum SentencePieceTokenizerError: Error, LocalizedError {
    case fileUnreadable(URL)
    case unsupportedModel(String)
    case missingSpecialToken(String)
    case tooLong(subwords: Int, seqLen: Int, slots: Int, maxWords: Int)

    var errorDescription: String? {
        switch self {
        case .fileUnreadable(let url):
            return "Could not read tokenizer file at \(url.lastPathComponent)."
        case .unsupportedModel(let type):
            return "tokenizer.json holds a \(type) model; this tokenizer only supports Unigram (CamemBERT)."
        case .missingSpecialToken(let token):
            return "Special token \(token) not found in the tokenizer vocabulary."
        case .tooLong(let subwords, let seqLen, let slots, let maxWords):
            return "Sentence needs \(subwords) subwords (limit \(seqLen)) and \(slots) word slots "
                 + "(limit \(maxWords)); split or truncate it before encoding."
        }
    }
}

extension SentencePieceEncodedSentence {
    /// MLMultiArrays named like the model's inputs: "input_ids" and "word_index" (Int32).
    func multiArrays() throws -> (inputIDs: MLMultiArray, wordIndex: MLMultiArray) {
        return (try Self.makeArray(inputIDs), try Self.makeArray(wordIndex))
    }
    private static func makeArray(_ values: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
        let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: values.count)
        for (i, v) in values.enumerated() { pointer[i] = v }
        return array
    }
}

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
final class SentencePieceTokenizer: SubwordEncoder {
    let padID: Int32
    let startID: Int32      // <s>, plays the role of [CLS]
    let endID: Int32        // </s>, plays the role of [SEP]
    let unkID: Int32
    var showSentPieces: Bool = false
    private let pieces: [String: (id: Int32, score: Double)]
    private let maxPieceLength: Int         // in Unicode scalars
    private let unkScore: Double
    private static let marker = "\u{2581}"  // "▁"
    private let idToPieces: [String]
    init(tokenizerJSON url: URL) throws {
        guard let data = try? Data(contentsOf: url) else { throw SentencePieceTokenizerError.fileUnreadable(url) }
        let file = try JSONDecoder().decode(SentencePieceTokenizerFile.self, from: data)
        guard file.model.type == "Unigram" else { throw SentencePieceTokenizerError.unsupportedModel(file.model.type) }
        let vocab = file.model.vocab

        func id(of token: String) throws -> Int32 {
            guard let index = vocab.firstIndex(where: { $0.piece == token }) else {
                throw SentencePieceTokenizerError.missingSpecialToken(token)
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
    func encode(words: [String], seqLen: Int, maxWords: Int) throws -> SentencePieceEncodedSentence {
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
            if showSentPieces {
                pieceStrings.append(wordIDs.map {idToPieces[Int($0)]})
            }
        }
        ids.append(endID)

        guard ids.count <= seqLen, wordIndex.count <= maxWords else {
            throw SentencePieceTokenizerError.tooLong(subwords: ids.count, seqLen: seqLen,
                                         slots: wordIndex.count, maxWords: maxWords)
        }
        let length = ids.count
        ids += [Int32](repeating: padID, count: seqLen - ids.count)
        wordIndex += [Int32](repeating: -1, count: maxWords - wordIndex.count)
        return SentencePieceEncodedSentence(inputIDs: ids, wordIndex: wordIndex,
                                            wordCount: words.count, length: length, sentPieces: showSentPieces ? pieceStrings : nil)
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

class BERTlikePipelineWithSentencePieceTokenizerLoader: ObservableObject, PipelineLoader{
    @Published var loadingProgress: Double = min(1.0, 0.0)
    @Published var statusMessage: String = "Waiting to load..."
    @Published var loadingComplete: Bool = false
    
    var sentPieceTokenizer: SentencePieceTokenizer?
    var taggerModel: MLModel?
    var labels: BERTpipeHelpers.LabelVocabsForBERTlike?
    let description: String = "BertLike pipeline with SentencePiece tok"
    
    var seqLen: Int = 512
    var maxWords: Int = 192
    let runExplicit: Bool = true
    
    // super lightweight init
    init( ){ }
    
    func convertToRealPipeline(
        sentPieceTokenizer: SentencePieceTokenizer,
        taggerModel: MLModel,
        labels: BERTpipeHelpers.LabelVocabsForBERTlike,
        seqLen: Int,
        maxWords: Int,
        languageCode: String,
        treebank: String,
        runExplicitValue: Bool
    ) throws -> BERTlikePipelineWithSentencePieceTokenizer{
        print("calling converter")
        return BERTlikePipelineWithSentencePieceTokenizer(
            taggerModel: taggerModel,
            sentPieceTokenizer: sentPieceTokenizer,
            labels: labels,
            seqLen: seqLen,
            maxWords: maxWords,
            runExplicitValue: runExplicitValue
        )
    }
}
    

final class BERTlikePipelineWithSentencePieceTokenizer: PipelineHelper, SubtokenAwarePipelineHelper, PipelineLoader {
    private let taggerModel: MLModel
    let labels: BERTpipeHelpers.LabelVocabsForBERTlike
    let description: String = "BERTlikePipeline with sent piece tokenizer"

    let sentPieceTokenizer: SentencePieceTokenizer
    let seqLen: Int
    let maxWords: Int
    let runExplicit: Bool

    init(
        taggerModel: MLModel,
        sentPieceTokenizer: SentencePieceTokenizer,
        labels: BERTpipeHelpers.LabelVocabsForBERTlike,
        seqLen: Int,
        maxWords: Int,
        runExplicitValue: Bool
    ){
        self.taggerModel = taggerModel
        self.sentPieceTokenizer = sentPieceTokenizer
        self.labels = labels
        self.seqLen = seqLen
        self.maxWords = maxWords
        self.runExplicit = runExplicitValue
    }
    // MARK: Running the model
    private func predictSentencePiece(_ encoded: SentencePieceEncodedSentence) throws -> MLFeatureProvider {
        let arrays = try encoded.multiArrays()
        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: arrays.inputIDs),
            "word_index": MLFeatureValue(multiArray: arrays.wordIndex),
        ])
        do {
            return try taggerModel.prediction(from: inputs)   // see point 1
        } catch {
            throw PipelineError.ProcessingError.predictionFailed(error)
        }
    }

    // MARK: Decoding
    private func decodeSentencePiece(_ output: MLFeatureProvider, words: [String],
                        sentencePieces: [[String]]?) throws -> [Token] {
        /// 6 padded output tensors -> labelled tokens. Only the first (words + 1) cols mean anything, rest is PAD
        let n = words.count + 1
        let upos = try BERTpipeHelpers.LogitReaderForBERTlike(output, "upos_logits", rank: 3, rows: n, labels: labels.upos.itos.count)
        let feats = try BERTpipeHelpers.LogitReaderForBERTlike(output, "feats_logits", rank: 3, rows: n, labels: labels.feats.itos.count)
        let lemmaRules = try BERTpipeHelpers.LogitReaderForBERTlike(output, "lemma_rule_logits", rank: 3, rows: n,
                                         labels: labels.lemmaRule.itos.count)
        let arc = try BERTpipeHelpers.LogitReaderForBERTlike(output, "arc_logits", rank: 3, rows: n)
        let deprels = try BERTpipeHelpers.LogitReaderForBERTlike(output, "label_logits", rank: 4, rows: n,
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
            throw PipelineError.GenericError.unexpectedOutput(
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
                subTokens: sentencePieces?[i - 1]
            ))
            if runExplicit{
                var subels: String = "empty"
                let tidy1 = sentencePieces?[i-1]
                if let success = tidy1{
                    subels = success.joined(separator: "/")
                }
                print("\(form) :: \(subels)")
            }
        }
        return tokens
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

        var sentPieceTokenizer = self.sentPieceTokenizer                  // a copy; the vocabulary isn't duplicated
        sentPieceTokenizer.showSentPieces = myConfig.exportConfig.getsubtokens
        var currentSentpieceCount: Int = -3
        do {
            guard let encoded = try? sentPieceTokenizer.encode(words: sentence.tokens, seqLen: seqLen, maxWords: maxWords
                ) else {
                return OnSentResult(sentence: sentence, resultType: .otherError, decoded: [])
            }
            currentSentpieceCount = encoded.validSlots
            let output = try predictSentencePiece(encoded) //
            let decoded = try decodeSentencePiece(output, words: sentence.tokens, sentencePieces: encoded.sentPieces) // same as decode in WP methods ?
            return OnSentResult(sentence: sentence,  subtokCount: currentSentpieceCount, resultType: .success, decoded: decoded)
        } catch WordPieceError.tooManySubwords {
            return OnSentResult(sentence: sentence,  subtokCount: currentSentpieceCount, resultType: .tooManySubtoks, decoded: [])
        } catch WordPieceError.tooManyWords {                              // backstop; the guard above catches this first
            return OnSentResult(sentence: sentence, resultType: .tooManyWords, decoded: [])
        } catch {
            if runExplicit { print("sentence failed: \(error.localizedDescription)") }
            return OnSentResult(sentence: sentence, resultType: .otherError, decoded: [])
        }
    }
}


enum ArrayMakingMethods{
    case cnnbilstm
    case sentencepieceencodedsentence
    case wordpieceencodedsentence
    var methodList: [String]{
        switch self{
                case .cnnbilstm : return ["makeIntArray" ,"makeCharIdArray", "parserArgmax"]
        case .sentencepieceencodedsentence, .wordpieceencodedsentence: return ["multiArrays", "makeArray"]
            
        }
    }

    
}

