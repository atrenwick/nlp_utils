//
//  WordPieceToksForBert.swift
//  Tagger
//
//  Created by Adam on 17/10/2026.
//
//  swift to build the two inputs the converted DistilBERT model expects:
//      input_ids   [1, seqLen]    [CLS] + subwords of every word + [SEP], padded with the pad id
//      word_index  [1, maxWords]  position of each word's first subword; slot 0 is ROOT -> [CLS];
//                                 padded with -1
//
//  Each word tokenised on its own, as train_bert.py does it, using same
//  pipeline as Hugging Face's BertTokenizerFast:
//      1. clean      drop NUL / U+FFFD / control characters, map whitespace to " "
//      2. CJK        put spaces around CJK ideographs (tokenize_chinese_chars)
//      3. accents    NFD, drop combining marks (only if stripping accents)
//      4. lowercase  per-scalar lowercase mapping (only if do_lower_case)
//      5. split      on whitespace; every punctuation character becomes its own token
//      6. WordPiece  greedy longest-match-first against vocab.txt, "##" for continuations;
//                    a token that can't be fully matched (or is > 100 characters) becomes [UNK]
//
//  A word that produces no pieces at all becomes a single [UNK], as in train_bert.py.
//
//  Everything works on Unicode scalars, not Swift Characters, because Python and Rust
//  iterate code points and Swift Characters merge combining sequences. The vocabulary is
//  keyed by UTF-8 bytes for the same reason: Swift String equality treats canonically
//  equivalent strings ("é" vs "e" + U+0301) as equal, which Python's dict does not.
//
//  Verify against Python with checkAgainstGolden(at:) before trusting any model output.

import Foundation
import CoreML
import SwiftUI

// MARK: - Errors
enum WordPieceError: Error, LocalizedError {
    case vocabUnreadable(URL)
    case missingSpecialToken(String)
    case missingSetting(String)
    case tooManyWords(have: Int, limit: Int)
    case tooManySubwords(have: Int, limit: Int)
    case tokenizerTryError
    case wordPieceTokenizerError
    case other
    var errorDescription: String? {
        switch self {
        case .other:
            return "Other type of error"
        case .wordPieceTokenizerError:
            return "error encoding after tokenizer made"
        case .tokenizerTryError:
            return "Try failed in test funct"
        case .vocabUnreadable(let url):
            return "Couldn't read the vocabulary file at \(url.lastPathComponent)"
        case .missingSpecialToken(let name):
            return "Special token \(name) isn't in the vocabulary"
        case .missingSetting(let name):
            return "tokenizer_config.json has no \"\(name)\"; pass it explicitly when creating the tokenizer"
        case .tooManyWords(let have, let limit):
            return "Sentence has \(have) words; the model accepts at most \(limit)"
        case .tooManySubwords(let have, let limit):
            return "Sentence needs \(have) subword tokens; the model accepts at most \(limit)"
        }
    }
}

// MARK: - Output type as struct :: data
struct WordPieceEncodedSentence {
    /// Length seqLen, padded with the pad id.
    let inputIDs: [Int32]
    /// Length maxWords, padded with -1. Element 0 is the ROOT slot.
    let wordIndex: [Int32]
    /// Number of real words. Read the first wordCount + 1 rows/columns of each model output.
    let wordCount: Int
    /// The subword strings for each word (e.g. ["play", "##ing"]), aligned with the input
    /// words. nil unless the tokenizer's showWordPieces is true.
    let wordPieces: [[String]]?
}
// extension on this struct to group all the processing done on the data helf in the struct
extension WordPieceEncodedSentence {
    /// int32 MLMultiArrays shaped [1, seqLen] and [1, maxWords], ready for the model.
    func multiArrays() throws -> (inputIDs: MLMultiArray, wordIndex: MLMultiArray) {
        return (try Self.makeArray(inputIDs), try Self.makeArray(wordIndex))
    }

    private static func makeArray(_ values: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
        let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: values.count)
        for (i, value) in values.enumerated() { pointer[i] = value }
        return array
    }
}

// MARK: - Tokenizer
struct WordPieceTokenizer: Sendable {
    
    var showWordPieces: Bool = false
    let clsID: Int32
    let sepID: Int32
    let padID: Int32
    let unkID: Int32

    private let vocab: [[UInt8]: Int32]
    private let idToToken: [[UInt8]]               // id -> token bytes, for showing word pieces
    private let specialTokenIDs: [String: Int32]
    private let continuingPrefix: [UInt8]
    private let maxInputCharsPerWord: Int
    private let lowercase: Bool
    private let stripAccents: Bool
    private let tokenizeChineseChars: Bool

    /// - Parameters:
    ///   - vocabURL: tokenizer/vocab.txt written by train_bert.py.
    ///   - configURL: tokenizer/tokenizer_config.json (supplies casing settings).
    ///   - doLowerCase, stripAccents, tokenizeChineseChars: explicit overrides. If
    ///     doLowerCase is neither passed nor in the config, init throws rather than guessing,
    ///     since a wrong guess silently changes token ids for capitalised words.
    init(vocabURL: URL,
         configURL: URL? = nil,
         doLowerCase: Bool? = nil,
         stripAccents: Bool? = nil,
         tokenizeChineseChars: Bool? = nil,
         continuingPrefix: String = "##",
         maxInputCharsPerWord: Int = 100) throws {

        // vocab.txt: one token per line, id = line number. Split on the 0x0A byte (not on
        // Characters, which would treat "\r\n" as one line break).
        let data: Data
        do { data = try Data(contentsOf: vocabURL) } catch { throw WordPieceError.vocabUnreadable(vocabURL) }
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }
        let tokenBytes = lines.map { Array($0) }
        var table = [[UInt8]: Int32](minimumCapacity: tokenBytes.count)
        for (index, bytes) in tokenBytes.enumerated() {
            table[bytes] = Int32(index)             // a later duplicate wins, as in Hugging Face
        }
        var config: [String: Any] = [:]
        if let configURL {
            let raw = try Data(contentsOf: configURL)
            config = (try JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? [:]
        }

        guard let lower = doLowerCase ?? (config["do_lower_case"] as? Bool) else {
            throw WordPieceError.missingSetting("do_lower_case")
        }
        self.lowercase = lower
        // strip_accents: explicit -> config (null counts as absent) -> follows lowercasing
        self.stripAccents = stripAccents ?? (config["strip_accents"] as? Bool) ?? lower
        self.tokenizeChineseChars = tokenizeChineseChars
            ?? (config["tokenize_chinese_chars"] as? Bool) ?? true

        func special(_ key: String, _ fallback: String) throws -> (name: String, id: Int32) {
            let name = (config[key] as? String) ?? fallback
            guard let id = table[Array(name.utf8)] else { throw WordPieceError.missingSpecialToken(name) }
            return (name, id)
        }
        let cls = try special("cls_token", "[CLS]")
        let sep = try special("sep_token", "[SEP]")
        let pad = try special("pad_token", "[PAD]")
        let unk = try special("unk_token", "[UNK]")
        self.clsID = cls.id
        self.sepID = sep.id
        self.padID = pad.id
        self.unkID = unk.id

        // A word that is exactly a special token ("[SEP]") maps to its id, as in Hugging Face.
        // (A special token embedded inside a longer word is not treated specially here.)
        var specials = [cls.name: cls.id, sep.name: sep.id, pad.name: pad.id, unk.name: unk.id]
        let maskName = (config["mask_token"] as? String) ?? "[MASK]"
        if let maskID = table[Array(maskName.utf8)] { specials[maskName] = maskID }
        self.specialTokenIDs = specials

        self.vocab = table
        self.idToToken = tokenBytes               // shares storage with the dictionary keys
        self.continuingPrefix = Array(continuingPrefix.utf8)
        self.maxInputCharsPerWord = maxInputCharsPerWord
    }

    // MARK: Public API

    /// Subword ids for one word. Never empty: falls back to a single [UNK].
    func pieces(for word: String) -> [Int32] {
        if let id = specialTokenIDs[word] { return [id] }
        var ids: [Int32] = []
        for token in preTokenize(normalize(word)) {
            ids.append(contentsOf: wordPiece(token))
        }
        return ids.isEmpty ? [unkID] : ids
    }
    /// The subword strings for one word, e.g. ["play", "##ing"]. Always available,
    /// independent of showWordPieces.
    func subtokens(for word: String) -> [String] {
        strings(for: pieces(for: word))
    }

    /// Unpadded encoding: [CLS] pieces... [SEP] and the ROOT-first word index.
    func encodeUnpadded(words: [String]) -> (inputIDs: [Int32], wordIndex: [Int32]) {
        let result = encodeDetailed(words: words, collectPieces: false)
        return (result.inputIDs, result.wordIndex)
    }
    
    private func encodeDetailed(words: [String], collectPieces: Bool)
        -> (inputIDs: [Int32], wordIndex: [Int32], pieces: [[Int32]]) {
        var ids: [Int32] = [clsID]
        var wordIndex: [Int32] = [0]                    // ROOT slot points at [CLS]
        var perWord: [[Int32]] = []
        for word in words {
            wordIndex.append(Int32(ids.count))
            let wordPieces = pieces(for: word)
            ids.append(contentsOf: wordPieces)
            if collectPieces { perWord.append(wordPieces) }
        }
        ids.append(sepID)
        return (ids, wordIndex, perWord)
    }
    
    private func strings(for ids: [Int32]) -> [String] {
        ids.map { String(decoding: idToToken[Int($0)], as: UTF8.self) }
    }
    /// Padded encoding for the fixed-length Core ML model. Use the same seqLen and maxWords
    /// the model was converted with (convert_bert.py prints them).
    func encode(words: [String], seqLen: Int, maxWords: Int) throws -> WordPieceEncodedSentence? {
        let detailed = encodeDetailed(words: words, collectPieces: showWordPieces)
        let ids = detailed.inputIDs
        let wordIndex = detailed.wordIndex
        guard wordIndex.count <= maxWords else {
//            return nil
            throw WordPieceError.tooManyWords(have: words.count, limit: maxWords - 1)
        }
        guard ids.count <= seqLen else {
//            return nil
                        throw WordPieceError.tooManySubwords(have: ids.count, limit: seqLen)
        }
        return WordPieceEncodedSentence(
            inputIDs: ids + [Int32](repeating: padID, count: seqLen - ids.count),
            wordIndex: wordIndex + [Int32](repeating: -1, count: maxWords - wordIndex.count),
            wordCount: words.count,
            wordPieces: showWordPieces ? detailed.pieces.map { strings(for: $0) } : nil
        )
    }
    // MARK: Normalisation and pre-tokenisation

    private func normalize(_ word: String) -> [Unicode.Scalar] {
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(word.unicodeScalars.count)
        for scalar in word.unicodeScalars {
            if scalar.value == 0 || scalar.value == 0xFFFD || Self.isControl(scalar) { continue }
            let mapped: Unicode.Scalar = Self.isWhitespace(scalar) ? " " : scalar
            if tokenizeChineseChars && Self.isCJK(mapped) {
                scalars.append(" ")
                scalars.append(mapped)
                scalars.append(" ")
            } else {
                scalars.append(mapped)
            }
        }
        if stripAccents {
            let decomposed = String(String.UnicodeScalarView(scalars)).decomposedStringWithCanonicalMapping
            scalars = decomposed.unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark }
        }
        if lowercase {
            scalars = scalars.flatMap { Array($0.properties.lowercaseMapping.unicodeScalars) }
        }
        return scalars
    }

    private func preTokenize(_ scalars: [Unicode.Scalar]) -> [[Unicode.Scalar]] {
        var tokens: [[Unicode.Scalar]] = []
        var current: [Unicode.Scalar] = []
        for scalar in scalars {
            if Self.isWhitespace(scalar) {
                if !current.isEmpty { tokens.append(current); current = [] }
            } else if Self.isPunctuation(scalar) {
                if !current.isEmpty { tokens.append(current); current = [] }
                tokens.append([scalar])
            } else {
                current.append(scalar)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: WordPiece

    private func wordPiece(_ token: [Unicode.Scalar]) -> [Int32] {
        if token.count > maxInputCharsPerWord { return [unkID] }

        // UTF-8 bytes of the token plus the byte offset where each scalar starts, so a
        // substring [start, end) in scalars is one slice of bytes.
        var bytes: [UInt8] = []
        var offsets: [Int] = []
        for scalar in token {
            offsets.append(bytes.count)
            bytes.append(contentsOf: String(scalar).utf8)
        }
        offsets.append(bytes.count)

        var ids: [Int32] = []
        var start = 0
        while start < token.count {
            var end = token.count
            var found: Int32?
            while start < end {
                var key: [UInt8] = start > 0 ? continuingPrefix : []
                key.append(contentsOf: bytes[offsets[start]..<offsets[end]])
                if let id = vocab[key] { found = id; break }
                end -= 1
            }
            guard let id = found else { return [unkID] }    // any failure -> whole token is [UNK]
            ids.append(id)
            start = end
        }
        return ids
    }


    // MARK: Character classes (match Hugging Face's BertNormalizer / BertPreTokenizer)
    private static func isWhitespace(_ s: Unicode.Scalar) -> Bool {
        s == "\t" || s == "\n" || s == "\r" || s.properties.isWhitespace
    }
    private static func isControl(_ s: Unicode.Scalar) -> Bool {
        if s == "\t" || s == "\n" || s == "\r" { return false }
        switch s.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned: return true
        default: return false
        }
    }
    private static func isPunctuation(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 33...47, 58...64, 91...96, 123...126: return true      // all ASCII punctuation and symbols
        default: break
        }
        switch s.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }
    private static func isCJK(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0x2A700...0x2B73F,
             0x2B740...0x2B81F, 0x2B820...0x2CEAF, 0xF900...0xFAFF, 0x2F800...0x2FA1F:
            return true
        default:
            return false
        }
    }
}

// MARK: - extension on struct to enable checking against the Python tokenizer
extension WordPieceTokenizer {
    private struct GoldenCase: Decodable {
        let words: [String]
        let inputIDs: [Int]
        let wordIndex: [Int]
        enum CodingKeys: String, CodingKey {
            case words
            case inputIDs = "input_ids"
            case wordIndex = "word_index"
        }
    }

    /// Runs every case in tokenizer_golden.json (written by train_bert.py) and returns a
    /// description of each mismatch. An empty array means this tokenizer agrees with Python.
    func checkAgainstGolden(fileNameChunk: String) throws -> [String] {
        guard let url = Bundle.main.url(forResource: fileNameChunk, withExtension: "json") else {
            throw PipelineError.LoadingError.configFileLoadError(name: fileNameChunk.appending(".json"))
        }
        
        let cases = try JSONDecoder().decode([GoldenCase].self, from: Data(contentsOf: url))
        var failures: [String] = []
        var matchCount: Int = 0
        for (n, golden) in cases.enumerated() {
            let got = encodeUnpadded(words: golden.words)
            let gotIDs = got.inputIDs.map { Int($0) }
            let gotIndex = got.wordIndex.map { Int($0) }
            if gotIDs != golden.inputIDs || gotIndex != golden.wordIndex {
                failures.append("""
                case \(n) \(golden.words.prefix(8))
                  expected ids \(golden.inputIDs.prefix(40))
                  got      ids \(gotIDs.prefix(40))
                """)
            } else {
                matchCount += 1
                let printstring = "case \(n) \(golden.words.prefix(8)) :: \(golden.inputIDs.prefix(40)) ==  \(gotIDs.prefix(40))"
                print("\(printstring)  ::match \(matchCount)")
            }
        }
        return failures
    }

    static func fromBundle(_ bundle: Bundle = .main, languageCode: String, treebank: String, vx: String) throws -> WordPieceTokenizer {
        guard let vocab = bundle.url(forResource: "\(languageCode)_distilbert_tok_vocab_\(treebank)\(vx)", withExtension: "txt") else {
            throw WordPieceError.vocabUnreadable(URL(fileURLWithPath: "\(languageCode)_distilbert_tok_vocab_\(treebank)\(vx).txt"))
        }
        print("got vocab txt")
        let settings = bundle.url(forResource: "\(languageCode)_distilbert_wordpiece_settings_\(treebank)\(vx)", withExtension: "json")
        return try WordPieceTokenizer(vocabURL: vocab, configURL: settings)
    }
}
