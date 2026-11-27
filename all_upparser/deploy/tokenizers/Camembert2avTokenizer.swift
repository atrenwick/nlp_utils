//
//  Camembert2avTokenizer.swift
//  Tagger
//
//  Word-by-word tokenizer matching almanach/camembertav2-base's tokenizer.json:
//    normalizer     : \p{Z} -> " ", then delete controls / Cf / Co / Cs / U+FE0F  (cased, no accent stripping)
//    pre_tokenizer  : space runs (<=4) isolated, lone " " removed, elision/clitic/punctuation regex,
//                     then a fixed list of emoji isolated
//    model          : WordPiece, "##" prefix, max_input_chars_per_word from the file (16)
//    post-processor : [CLS] ... [SEP]

import Foundation

/// NSRegularExpression is immutable and thread-safe once built but isn't declared Sendable;
/// this box lets the tokenizer struct stay Sendable.
private final class SplitRegex: @unchecked Sendable {
    let regex: NSRegularExpression
    init(_ pattern: String) throws { self.regex = try NSRegularExpression(pattern: pattern) }
}

/// The exact patterns from tokenizer.json. init() verifies the loaded file contains these,
/// so the hand-written steps below can't silently drift from the file.
private enum CamembertV2Pipeline {
    static let replaceSeparators = #"\p{Z}"#
    static let removeControls = #"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]|\p{Cf}|\p{Co}|\p{Cs}|[\uFE0F]"#
    static let spaceRuns = "[ ]{1,4}"
    static let lonelySpace = "^ $"
    static let elisionAndPunct = #"(?i:\b[cmnjstdl]|qu|puisqu|lorsqu|quelqu|presqu|quoiqu|jusqu)['´’]|['´’](?i:[sdmt]|ll|ve|re)\b|\p{P}{1,4}|[^\p{L}\p{N}\p{Z}]"#
}

struct CamemBERTv2Tokenizer: Sendable, BERTlikeTokenizerHelper,WPieceHelper {
    var showPieces: Bool = false
    var showWordPieces: Bool = false
    let clsID: Int32
    let sepID: Int32
    let padID: Int32
    let unkID: Int32

    private let vocab: [[UInt8]: Int32]
    let idToToken: [[UInt8]]
    private let specialTokenIDs: [String: Int32]
    private let continuingPrefix: [UInt8]
    private let maxInputCharsPerWord: Int
    private let splitRegex: SplitRegex
    private let isolatedScalars: Set<Unicode.Scalar>

    /// - Parameter tokenizerJSONURL: the tokenizer.json saved with the fine-tuned model.
    init(tokenizerJSONURL: URL) throws {
        let data: Data
        do { data = try Data(contentsOf: tokenizerJSONURL) }
        catch { throw PipelineError.TokPieceError.vocabUnreadable(tokenizerJSONURL) }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = root["model"] as? [String: Any],
              (model["type"] as? String) == "WordPiece", // was WPiece
              let vocabDict = model["vocab"] as? [String: Int]
        else { throw PipelineError.TokPieceError.missingSetting("model.vocab (WordPiece)") }

        self.isolatedScalars = try Self.verifyPipeline(root)
        self.splitRegex = try SplitRegex(CamembertV2Pipeline.elisionAndPunct)
        self.continuingPrefix = Array(((model["continuing_subword_prefix"] as? String) ?? "##").utf8)
        self.maxInputCharsPerWord = (model["max_input_chars_per_word"] as? Int) ?? 100
        // vocabulary: token bytes -> id, plus id -> token bytes for showing pieces
        let maxID = vocabDict.values.max() ?? -1
        var table = [[UInt8]: Int32](minimumCapacity: vocabDict.count)
        var byID = [[UInt8]](repeating: [], count: maxID + 1)
        for (token, id) in vocabDict {
            let bytes = Array(token.utf8)
            table[bytes] = Int32(id)
            byID[id] = bytes
        }
        self.vocab = table
        self.idToToken = byID

        // special tokens
        var added: [String: Int32] = [:]
        var specials: [String: Int32] = [:]
        for item in (root["added_tokens"] as? [[String: Any]]) ?? [] {
            guard let content = item["content"] as? String, let id = item["id"] as? Int else { continue }
            added[content] = Int32(id)
            if (item["special"] as? Bool) ?? true { specials[content] = Int32(id) }
        }
        func special(_ name: String) throws -> Int32 {
            if let id = added[name] { return id }
            if let id = vocabDict[name] { return Int32(id) }
            throw PipelineError.TokPieceError.missingSpecialToken(name)
        }
        self.clsID = try special("[CLS]")
        self.sepID = try special("[SEP]")
        self.padID = try special("[PAD]")
        self.unkID = try special("[UNK]")
        self.specialTokenIDs = specials
    }

    /// Adapt the resource name / folder to however you ship the file.
    static func fromBundle(_ bundle: Bundle = .main,  languageCode: String, treebank: String) throws -> CamemBERTv2Tokenizer {

        guard let url = bundle.url(forResource: "\(languageCode)_camembertav2_tok_vocab_\(treebank)", withExtension: "json") else {
            throw PipelineError.TokPieceError.vocabUnreadable(bundle.bundleURL)
        }
        return try CamemBERTv2Tokenizer(tokenizerJSONURL: url)
    }

    // MARK: Public API (same shape as WordPieceTokenizer)
    /// Subword ids for one word. Never empty: falls back to a single [UNK].
    func pieces(for word: String) -> [Int32] {
        if let id = specialTokenIDs[word] { return [id] }
        let ids = rawPieces(for: word)
        return ids.isEmpty ? [unkID] : ids
    }

    /// Like pieces(for:) but may be empty (a word that normalises away). Used by the golden check.
    func rawPieces(for word: String) -> [Int32] {
        var ids: [Int32] = []
        for token in preTokenize(normalize(word)) {
            ids.append(contentsOf: wordPiece(token))
        }
        return ids
    }
    // moved to extension
//    func subtokens(for word: String) -> [String] { strings(for: pieces(for: word)) }
    // moved to extension
//    func encodeUnpadded(words: [String]) -> (inputIDs: [Int32], wordIndex: [Int32]) {
//        let result = encodeDetailed(words: words, collectPieces: false)
//        return (result.inputIDs, result.wordIndex)
//    }

    func encode(words: [String], seqLen: Int, maxWords: Int) throws -> BERTpipeEncodedSentence? {
        let detailed = encodeDetailed(words: words, collectPieces: showWordPieces)
        let ids = detailed.inputIDs
        let wordIndex = detailed.wordIndex
        guard wordIndex.count <= maxWords else {
            throw PipelineError.TokPieceError.tooManyWords(have: words.count, limit: maxWords - 1)
        }
        guard ids.count <= seqLen else {
            throw PipelineError.TokPieceError.tooManySubwords(have: ids.count, limit: seqLen)
        }
        return WordPieceEncodedSentence(
            inputIDs: ids + [Int32](repeating: padID, count: seqLen - ids.count),
            wordIndex: wordIndex + [Int32](repeating: -1, count: maxWords - wordIndex.count),
            wordCount: words.count,
            length: ids.count,
            pieces: showWordPieces ? detailed.pieces.map { strings(for: $0) } : nil,
            validSlots: words.count + 1
        )
    }

//    private func encodeDetailed(words: [String], collectPieces: Bool)
//        -> (inputIDs: [Int32], wordIndex: [Int32], pieces: [[Int32]]) {
//        var ids: [Int32] = [clsID]
//        var wordIndex: [Int32] = [0]                    // ROOT slot points at [CLS]
//        var perWord: [[Int32]] = []
//        for word in words {
//            wordIndex.append(Int32(ids.count))
//            let wordPieces = pieces(for: word)
//            ids.append(contentsOf: wordPieces)
//            if collectPieces { perWord.append(wordPieces) }
//        }
//        ids.append(sepID)
//        return (ids, wordIndex, perWord)
//    }

//    private func strings(for ids: [Int32]) -> [String] {
//        ids.map { String(decoding: idToToken[Int($0)], as: UTF8.self) }
//    }

    // MARK: Normalizer
    // 1. every \p{Z} scalar -> " "   2. delete [\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f] | Cf | Co | Cs | U+FE0F
    // Note \t \n \r are NOT deleted. No lowercasing, no accent stripping, no Unicode normalisation.
    private func normalize(_ word: String) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(word.unicodeScalars.count)
        for s in word.unicodeScalars {
            switch s.properties.generalCategory {
            case .spaceSeparator, .lineSeparator, .paragraphSeparator:
                out.append(" ")
            case .format, .privateUse, .surrogate:
                continue
            default:
                let v = s.value
                if v <= 0x08 || v == 0x0B || v == 0x0C || (0x0E...0x1F).contains(v)
                    || (0x7F...0x9F).contains(v) || v == 0xFE0F { continue }
                out.append(s)
            }
        }
        return out
    }

    // MARK: Pre-tokenizer
    private func preTokenize(_ scalars: [Unicode.Scalar]) -> [[Unicode.Scalar]] {
        // Rules 1 + 2: isolate space runs in chunks of at most 4; a chunk of exactly one space is removed.
        var chunks: [[Unicode.Scalar]] = []
        var i = 0
        while i < scalars.count {
            var j = i
            if scalars[i] == " " {
                while j < scalars.count, scalars[j] == " " { j += 1 }
                var remaining = j - i
                while remaining > 0 {
                    let n = min(4, remaining)
                    if n > 1 { chunks.append([Unicode.Scalar](repeating: " ", count: n)) }
                    remaining -= n
                }
            } else {
                while j < scalars.count, scalars[j] != " " { j += 1 }
                chunks.append(Array(scalars[i..<j]))
            }
            i = j
        }
        // Rules 3 + 4
        var result: [[Unicode.Scalar]] = []
        for chunk in chunks {
            for part in splitByRegex(chunk) {
                result.append(contentsOf: splitIsolatedScalars(part))
            }
        }
        return result
    }

    /// Rule 3: Split(regex, Isolated): matches become their own piece, the gaps between them stay as pieces.
    private func splitByRegex(_ piece: [Unicode.Scalar]) -> [[Unicode.Scalar]] {
        // Fast path: a pure letters/digits run can't match any alternative (all need an apostrophe,
        // punctuation or a symbol), so skip the regex for the common case.
        if piece.allSatisfy(Self.isLetterOrNumber), !piece.contains(where: isolatedScalars.contains) {
            return [piece]
        }
        let text = NSString(string: String(String.UnicodeScalarView(piece)))
        var out: [[Unicode.Scalar]] = []
        var cursor = 0
        let matches = splitRegex.regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for m in matches {
            if m.range.location > cursor {
                let gap = NSRange(location: cursor, length: m.range.location - cursor)
                out.append(Array(text.substring(with: gap).unicodeScalars))
            }
            out.append(Array(text.substring(with: m.range).unicodeScalars))
            cursor = m.range.location + m.range.length
        }
        if cursor < text.length {
            out.append(Array(text.substring(from: cursor).unicodeScalars))
        }
        return out
    }

    /// Rule 4: isolate every scalar from the emoji list.
    private func splitIsolatedScalars(_ part: [Unicode.Scalar]) -> [[Unicode.Scalar]] {
        if !part.contains(where: isolatedScalars.contains) { return [part] }
        var out: [[Unicode.Scalar]] = []
        var current: [Unicode.Scalar] = []
        for s in part {
            if isolatedScalars.contains(s) {
                if !current.isEmpty { out.append(current); current = [] }
                out.append([s])
            } else {
                current.append(s)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private static func isLetterOrNumber(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    // MARK: WordPiece (greedy longest match; any failure -> whole pre-token is [UNK]) :: identical to same-named method in WordPieceTokenizer
    private func wordPiece(_ token: [Unicode.Scalar]) -> [Int32] {
        if token.count > maxInputCharsPerWord { return [unkID] }

        // UTF-8 bytes of token + byte offset where each scalar starts:: substr [start, end] in scalars = 1x slice of bytes
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

    // MARK: Verify tokenizer.json really is this pipeline
    private static func regex(_ d: [String: Any]) -> String? {
        (d["pattern"] as? [String: Any])?["Regex"] as? String
    }

    /// Throws unless tokenizer.json's normalizer and pre_tokenizer match what this file implements.
    /// Returns the emoji scalars from the 4th pre-tokenizer rule (a plain [...] character class).
    private static func verifyPipeline(_ root: [String: Any]) throws -> Set<Unicode.Scalar> {
        typealias P = CamembertV2Pipeline
        func unsupported(_ what: String) -> Error {
            PipelineError.TokPieceError.missingSetting("supported tokenizer.json (\(what))")
        }
        guard let norms = (root["normalizer"] as? [String: Any])?["normalizers"] as? [[String: Any]],
              norms.count == 2,
              regex(norms[0]) == P.replaceSeparators, norms[0]["content"] as? String == " ",
              regex(norms[1]) == P.removeControls, norms[1]["content"] as? String == ""
        else { throw unsupported("normalizer") }

        guard let pres = (root["pre_tokenizer"] as? [String: Any])?["pretokenizers"] as? [[String: Any]],
              pres.count == 4,
              pres.allSatisfy({ ($0["type"] as? String) == "Split" }),
              pres.map({ $0["behavior"] as? String }) == ["Isolated", "Removed", "Isolated", "Isolated"],
              regex(pres[0]) == P.spaceRuns,
              regex(pres[1]) == P.lonelySpace,
              regex(pres[2]) == P.elisionAndPunct,
              let emojiClass = regex(pres[3])
        else { throw unsupported("pre_tokenizer") }

        let scalars = Array(emojiClass.unicodeScalars)
        guard scalars.count > 2, scalars.first == "[", scalars.last == "]" else { throw unsupported("emoji class") }
        let body = scalars.dropFirst().dropLast()
        // a plain list of characters: no escapes, ranges or negation
        guard !body.contains("\\"), !body.contains("-"), !body.contains("^") else { throw unsupported("emoji class") }
        return Set(body)
    }
}

// MARK: Golden check
extension CamemBERTv2Tokenizer {
    /// Compares against golden_tokenizer.json written by dump_tokenizer_spec.py. Each golden text is fed
    /// through as ONE "word" (the pre-tokenizer handles the spaces, exactly as Hugging Face does).
    /// Returns human-readable mismatches; an empty array means every case matched.
    func checkAgainstGolden(url: URL) throws -> [String] {
        struct Case: Decodable { let text: String; let ids: [Int32]; let idsNoSpecial: [Int32] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let cases = try decoder.decode([Case].self, from: Data(contentsOf: url))

        var failures: [String] = []
        for c in cases {
            let got = rawPieces(for: c.text)
            if got != c.idsNoSpecial {
                failures.append("\(c.text.debugDescription)\n   expected \(c.idsNoSpecial)\n   got      \(got)")
            } else if [clsID] + got + [sepID] != c.ids {
                failures.append("\(c.text.debugDescription): special-token wrapping differs (expected \(c.ids))")
            }
        }
        return failures
    }
}
