//
//  RNNTokeniser.swift
//  Tagger
//
//  Created by 10/11/2026.
//
//  Swift port of RNNTagger's utf8-tokenize.perl
//  Perl option          ->  Swift
//    -e                     language: .english
//    -f                     language: .french
//    -F                     language: .oldFrench
//    -g                     germanOrdinals: true
//    -a <file>              knownTokens: try RNNTaggerTokenizer.loadKnownTokens(from: url)
//
//  Usage:
//      let tokenizer = RNNTaggerTokenizer(language: .french)
//      let sentences = tokenizer.tokenize("L'homme dit: « Oui. »")     // [[String]], one array per sentence
//      let perlOutput = tokenizer.tokenizedText(text)                   // exactly what the Perl script prints
//
//  The algorithm works on Unicode scalars, like Perl on decoded strings, not on Swift Characters.
//  The text is NOT normalised: if the tagger was trained on NFC text, pass in NFC text.
//  Can test with  `RNNTaggerTokenizer.selfTest()`. An empty result means all cases agree.
//
//  Two quirks of the Perl script are reproduced on purpose:
//   * the abbreviation test `$1 ne 'á'` compares a two-character capture with one character, so it is
//     always true and has no effect;
//   * a sentence break is removed (not just prevented) for listed tokens, initialisms like U.S.A.,
//     and (with -g) numbers such as "3.".
//
import Foundation

struct RNNTaggerTokenizer {

    enum Language {
        case other      // no clitic splitting (the script's default)
        case english    // -e
        case french     // -f
        case oldFrench  // -F
    }

    typealias Scalars = [Unicode.Scalar]

    let language: Language
    let germanOrdinals: Bool
    private let knownTokens: Set<Scalars>
    private let prefixClitic: NSRegularExpression?     // ^(PClitic)(.)
    private let suffixClitic: NSRegularExpression?     // (.)(FClitic)$

    init(language: Language = .other, germanOrdinals: Bool = false, knownTokens: [String] = []) {
        self.language = language
        self.germanOrdinals = germanOrdinals
        self.knownTokens = Set(knownTokens.map { Array($0.unicodeScalars) })

        // Patterns copied from the Perl script. U+2019 and U+00B4 are the typographic apostrophe and the
        // acute accent; U+00B7 is a middle dot.
        var prefix: String? = nil
        var suffix: String? = nil
        switch language {
        case .other:
            break
        case .english:
            suffix = "['\u{2019}\u{00B4}](?:s|re|ve|d|m|em|ll)|n['\u{2019}\u{00B4}]t"
        case .oldFrench:
            prefix = "(?:[cdgjklmnqst\u{00E7}]|antr|bon|cel|cest|ch|ensembl|entr|jusq|jusqu|qu|quanqu|saint|seint|tresqu|un)['\u{00B4}\u{2019}]"
            suffix = "\u{00B7}(l|m|s|ls)"
        case .french:
            prefix = "(?:[dcjlmnst]|qu|jusqu|lorsqu|quoiqu|puisqu)['\u{2019}\u{00B4}]"
            suffix = "-t-elles?|-t-ils?|-t-on|-ce|-elles?|-ils?|-je|-la|-les?|-leur|-lui|-m\u{00EA}mes?|-m['\u{2019}\u{00B4}]|-moi|-nous|-on|-toi|-tu|-t['\u{2019}\u{00B4}]|-vous|-en|-y|-ci|-l\u{00E0}"
        }
        // the patterns are fixed, so a compile failure would be a programming error
        self.prefixClitic = prefix.map { try! NSRegularExpression(pattern: "^(\($0))(.)", options: [.caseInsensitive]) }
        self.suffixClitic = suffix.map { try! NSRegularExpression(pattern: "(.)(\($0))$", options: [.caseInsensitive]) }
    }

    // MARK: - Public API
    /// Sentences of tokens. A blank line in the Perl output ends a sentence.
    func tokenize(_ text: String) -> [[String]] {
        var sentences: [[String]] = []
        var current: [String] = []
        for line in tokenizedScalars(text).split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {
                if !current.isEmpty { sentences.append(current); current = [] }
            } else {
                current.append(Self.string(from: Array(line)))
            }
        }
        if !current.isEmpty { sentences.append(current) }
        return sentences
    }

    /// Exactly what `perl utf8-tokenize.perl` prints: one token per line, a blank line after each sentence,
    /// and one extra newline at the very end.
    func tokenizedText(_ text: String) -> String {
        Self.string(from: tokenizedScalars(text))
    }

    /// Reads a word list like the Perl script's -a file: one entry per line, '#' starts a comment line,
    /// surrounding blanks are trimmed. Entries are tokens that must not be split further.
    static func loadKnownTokens(from url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let trim = CharacterSet(charactersIn: " \t\r\n")
        var tokens: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: trim)
            if line.isEmpty || line.hasPrefix("#") { continue }
            tokens.append(line)
        }
        return tokens
    }

    // MARK: - Character classes/sets/
    private static func scalarSet(_ codePoints: [UInt32]) -> Set<Unicode.Scalar> {
        Set(codePoints.compactMap { Unicode.Scalar($0) })
    }

    /// $PChar: cut off at the beginning of a word
    private static let leadingPunctuation: Set<Unicode.Scalar> = scalarSet([
        0x005B, // [
        0x00BF, // inverted question mark
        0x00A1, // inverted exclamation mark
        0x007B, // {
        0x0027, // '
        0x0060, // `
        0x0022, // "
        0x201A, // single low-9 quotation mark
        0x201E, // double low-9 quotation mark
        0x2020, // dagger
        0x2021, // double dagger
        0x2039, // single left-pointing angle quotation mark
        0x2018, // left single quotation mark
        0x2019, // right single quotation mark
        0x201C, // left double quotation mark
        0x201D, // right double quotation mark
        0x2022, // bullet
        0x2013, // en dash
        0x2014, // em dash
        0x203A, // single right-pointing angle quotation mark
        0x00BB, // right-pointing double angle quotation mark
        0x00AB, // left-pointing double angle quotation mark
    ])

    /// $FChar: cut off at the end of a word
    private static let trailingPunctuation: Set<Unicode.Scalar> = scalarSet([
        0x005D, // ]
        0x007D, // }
        0x0027, // '
        0x0060, // `
        0x0022, // "
        0x002C, // ,
        0x003B, // ;
        0x003A, // :
        0x0021, // !
        0x003F, // ?
        0x0025, // %
        0x201A, // single low-9 quotation mark
        0x201E, // double low-9 quotation mark
        0x2026, // horizontal ellipsis
        0x2020, // dagger
        0x2021, // double dagger
        0x2030, // per mille sign
        0x2039, // single left-pointing angle quotation mark
        0x2018, // left single quotation mark
        0x2019, // right single quotation mark
        0x201C, // left double quotation mark
        0x201D, // right double quotation mark
        0x2022, // bullet
        0x2013, // en dash
        0x2014, // em dash
        0x203A, // single right-pointing angle quotation mark
        0x00BB, // right-pointing double angle quotation mark
        0x00AB, // left-pointing double angle quotation mark
    ])

    /// characters that may follow sentence-final punctuation:  ) ] ' "
    private static let closers: Set<Unicode.Scalar> = [")", "]", "'", "\""]

    /// Perl's \s on decoded strings is the Unicode White_Space property
    private static func isSpace(_ s: Unicode.Scalar) -> Bool { s.properties.isWhitespace }

    /// Perl's \p{L}
    private static func isLetter(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }

    private static func string(from scalars: Scalars) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    // MARK: - Main loop

    private func tokenizedScalars(_ text: String) -> Scalars {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }      // optional byte order mark

        var out = Scalars()
        // Perl splits each line into whitespace-separated segments; line boundaries carry no other
        // meaning, so splitting the whole text on whitespace gives the same segments.
        for segment in scalars.split(whereSeparator: { Self.isSpace($0) }) {
            var s: Scalars = [" "]
            s += segment
            s.append(" ")
            s = Self.spacingEllipses(s)
            s = Self.spacingAfterPunctuation(s)
            for piece in s.split(separator: " ") {
                processToken(Array(piece), into: &out)
            }
        }
        out.append("\n")      // the script prints a final newline, which also ends the last sentence
        return out
    }

    /// s/(\.\.\.)/ ... /g
    private static func spacingEllipses(_ s: Scalars) -> Scalars {
        var result = Scalars()
        var i = 0
        while i < s.count {
            if i + 2 < s.count, s[i] == ".", s[i + 1] == ".", s[i + 2] == "." {
                result += [" ", ".", ".", ".", " "]
                i += 3
            } else {
                result.append(s[i])
                i += 1
            }
        }
        return result
    }

    /// s/([;\!\?])([^ ])/$1 $2/g   (matches do not overlap: the character after the punctuation is consumed)
    private static func spacingAfterPunctuation(_ s: Scalars) -> Scalars {
        var result = Scalars()
        var i = 0
        while i < s.count {
            let c = s[i]
            if (c == ";" || c == "!" || c == "?"), i + 1 < s.count, s[i + 1] != " " {
                result += [c, " ", s[i + 1]]
                i += 2
            } else {
                result.append(c)
                i += 1
            }
        }
        return result
    }

    // MARK: - One token
    private func processToken(_ token: Scalars, into out: inout Scalars) {
        var tok = token
        var suffix = Scalars()          // text that follows the token, built from the right
        if Self.endsSentence(tok) { suffix = ["\n"] }

        // separate punctuation and parentheses from the word
        while true {
            let n = tok.count
            if n >= 2, tok[0] == "(", !tok[1..<(n - 1)].contains(")") {
                // "(" in front: the rest of the token contains no ")" before its last character
                out += ["(", "\n"]
                tok.removeFirst()
            } else if n >= 2, tok[n - 1] == ")", !tok[0..<(n - 1)].contains("(") {
                suffix = [")", "\n"] + suffix
                tok.removeLast()
            } else if n >= 3, (tok[0] == "`" && tok[1] == "`") || (tok[0] == "," && tok[1] == ",") {
                out += [tok[0], tok[1], "\n"]
                tok.removeFirst(2)
            } else if n >= 3, tok[n - 1] == "'", tok[n - 2] == "'" {
                suffix = ["'", "'", "\n"] + suffix
                tok.removeLast(2)
            } else if n >= 2, Self.leadingPunctuation.contains(tok[0]) {
                out += [tok[0], "\n"]
                tok.removeFirst()
            } else if n >= 2, Self.trailingPunctuation.contains(tok[n - 1]) {
                suffix = [tok[n - 1], "\n"] + suffix
                tok.removeLast()
            } else if n >= 2, tok[n - 1] == ".",
                      Self.trailingPunctuation.contains(tok[n - 2]) || tok[n - 2] == ")" {
                // punctuation followed by a period: both are cut off
                let punctuation = tok[n - 2]
                tok.removeLast(2)
                suffix = [".", "\n"] + suffix
                if tok.isEmpty {
                    tok = [punctuation]
                } else {
                    suffix = [punctuation, "\n"] + suffix
                }
            } else {
                break
            }
        }

        // explicitly listed tokens are kept whole
        if knownTokens.contains(tok) {
            suffix = Self.removingSentenceBreak(suffix)
            out += tok; out.append("\n"); out += suffix
            return
        }

        // initialisms such as A. or U.S.A.
        if Self.isInitialism(tok) {
            suffix = Self.removingSentenceBreak(suffix)
            out += tok; out.append("\n"); out += suffix
            return
        }

        // disambiguate periods
        if tok.count >= 2, tok.last == ".", tok != [".", ".", "."] {
            if germanOrdinals && Self.isDigitsThenPeriod(tok) {
                suffix = Self.removingSentenceBreak(suffix)      // "3." stays one token
            } else {
                tok.removeLast()
                suffix = [".", "\n"] + suffix
                if knownTokens.contains(tok) {
                    out += tok; out.append("\n"); out += suffix
                    return
                }
            }
        }

        // cut off clitics
        while tok.count >= 3, tok[0] == "-", tok[1] == "-" {
            out += ["-", "-", "\n"]
            tok.removeFirst(2)
        }
        while let (clitic, rest) = splitLeadingClitic(tok) {
            out += Self.normalizingApostrophes(clitic)
            out.append("\n")
            tok = rest
        }
        while tok.count >= 3, tok[tok.count - 1] == "-", tok[tok.count - 2] == "-" {
            suffix = ["-", "-", "\n"] + suffix
            tok.removeLast(2)
        }
        while let (rest, clitic) = splitTrailingClitic(tok) {
            suffix = Self.normalizingApostrophes(clitic) + ["\n"] + suffix
            tok = rest
        }

        out += tok; out.append("\n"); out += suffix
    }

    /// /^(.*[^.])?[.!?][)\]\'\"]*$/ or /।$/
    private static func endsSentence(_ t: Scalars) -> Bool {
        guard let last = t.last else { return false }
        if last == "\u{0964}" { return true }                         // Devanagari danda
        var end = t.count
        while end > 0, closers.contains(t[end - 1]) { end -= 1 }
        guard end > 0, t[end - 1] == "." || t[end - 1] == "!" || t[end - 1] == "?" else { return false }
        let mark = end - 1
        return mark == 0 || t[mark - 1] != "."
    }

    /// $suffix =~ s/^([)\]\'\"]*)\n$/$1/ : drops one newline that directly follows the closing characters.
    /// Because Perl's $ also matches before a final newline, "...\n\n" loses just its first newline.
    private static func removingSentenceBreak(_ s: Scalars) -> Scalars {
        var i = 0
        while i < s.count, closers.contains(s[i]) { i += 1 }
        guard i < s.count, s[i] == "\n" else { return s }
        let rest = s.count - (i + 1)
        guard rest == 0 || (rest == 1 && s[i + 1] == "\n") else { return s }
        return Array(s[..<i]) + Array(s[(i + 1)...])
    }

    /// /^(\p{L}\.)+$/
    private static func isInitialism(_ t: Scalars) -> Bool {
        guard t.count >= 2, t.count % 2 == 0 else { return false }
        var k = 0
        while k < t.count {
            guard isLetter(t[k]), t[k + 1] == "." else { return false }
            k += 2
        }
        return true
    }

    /// /^[0-9]+\.$/
    private static func isDigitsThenPeriod(_ t: Scalars) -> Bool {
        guard t.count >= 2, t[t.count - 1] == "." else { return false }
        return t[0..<(t.count - 1)].allSatisfy { $0.value >= 0x30 && $0.value <= 0x39 }
    }

    /// tr/'’´/'''/
    private static func normalizingApostrophes(_ s: Scalars) -> Scalars {
        s.map { (c: Unicode.Scalar) -> Unicode.Scalar in
            (c == "\u{2019}" || c == "\u{00B4}") ? "'" : c
        }
    }

    // MARK: - Clitics (regular expressions copied from the Perl script, case-insensitive)

    /// s/^($PClitic)(.)/$2/i  -> the clitic and the remaining word
    private func splitLeadingClitic(_ tok: Scalars) -> (clitic: Scalars, rest: Scalars)? {
        guard let regex = prefixClitic else { return nil }
        let str = Self.string(from: tok)
        let ns = str as NSString
        guard let match = regex.firstMatch(in: str, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let clitic = match.range(at: 1)
        return (Array(ns.substring(with: clitic).unicodeScalars),
                Array(ns.substring(from: NSMaxRange(clitic)).unicodeScalars))
    }

    /// s/(.)($FClitic)$/$1/i  -> the remaining word and the clitic (leftmost match, so the longest clitic)
    private func splitTrailingClitic(_ tok: Scalars) -> (rest: Scalars, clitic: Scalars)? {
        guard let regex = suffixClitic else { return nil }
        let str = Self.string(from: tok)
        let ns = str as NSString
        guard let match = regex.firstMatch(in: str, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let clitic = match.range(at: 2)
        return (Array(ns.substring(to: clitic.location).unicodeScalars),
                Array(ns.substring(with: clitic).unicodeScalars))
    }
}

// MARK: - Self test against the original Perl script
extension RNNTaggerTokenizer {
    private struct ReferenceCase {
        let name: String
        let language: Language
        let germanOrdinals: Bool
        let knownTokens: [String]
        let input: String
        let expected: String      // recorded from `perl utf8-tokenize.perl` with the matching options
    }

    /// Runs the recorded cases. Returns a description of every mismatch; an empty array means all agree.
    static func selfTest() -> [String] {
        var failures: [String] = []
        for c in referenceCases {
            let tokenizer = RNNTaggerTokenizer(language: c.language, germanOrdinals: c.germanOrdinals,
                                               knownTokens: c.knownTokens)
            let got = tokenizer.tokenizedText(c.input)
            if got != c.expected {
                failures.append("\(c.name): expected \(c.expected.debugDescription) but got \(got.debugDescription)")
            }
        }
        return failures
    }

    private static let referenceCases: [ReferenceCase] = [
        ReferenceCase(
            name: "default: punctuation, abbreviations, quotes",
            language: .other, germanOrdinals: false,
            knownTokens: [],
            input: "Hello, world! This is Dr. Smith (and U.S.A.) -- \"quoted\" text... Really?!\n(Yes.) He said: \"No.\" ``Odd'' quotes; fine.\n",
            expected: "Hello\n,\nworld\n!\n\nThis\nis\nDr\n.\n\nSmith\n(\nand\nU.S.A.\n)\n--\n\"\nquoted\n\"\ntext\n...\nReally\n?\n\n!\n\n(\nYes\n.\n)\n\nHe\nsaid\n:\n\"\nNo\n.\n\"\n\n``\nOdd\n''\nquotes\n;\nfine\n.\n\n\n"),
        ReferenceCase(
            name: "english clitics (-e)",
            language: .english, germanOrdinals: false,
            knownTokens: [],
            input: "I don't think John's dog isn't here. They're sure we'll see it; I'd say so, I'm sure.\n",
            expected: "I\ndo\nn't\nthink\nJohn\n's\ndog\nis\nn't\nhere\n.\n\nThey\n're\nsure\nwe\n'll\nsee\nit\n;\nI\n'd\nsay\nso\n,\nI\n'm\nsure\n.\n\n\n"),
        ReferenceCase(
            name: "french clitics (-f)",
            language: .french, germanOrdinals: false,
            knownTokens: [],
            input: "L'homme dit: \"Qu'est-ce que c'est?\" Donne-le-moi! Jusqu'à demain, est-il là? Viens-t-il aujourd'hui. D’accord, j´y vais.\n",
            expected: "L'\nhomme\ndit\n:\n\"\nQu'\nest\n-ce\nque\nc'\nest\n?\n\n\"\nDonne\n-le\n-moi\n!\n\nJusqu'\nà\ndemain\n,\nest\n-il\nlà\n?\n\nViens\n-t-il\naujourd'hui\n.\n\nD'\naccord\n,\nj'\ny\nvais\n.\n\n\n"),
        ReferenceCase(
            name: "old french (-F)",
            language: .oldFrench, germanOrdinals: false,
            knownTokens: [],
            input: "L'om dist qu'il l’ama·l ensembl'a Jusqu'a li. Saint'Pere aime·ls.\n",
            expected: "L'\nom\ndist\nqu'\nil\nl'\nama\n·l\nensembl'\na\nJusqu'\na\nli\n.\n\nSaint'\nPere\naime\n·ls\n.\n\n\n"),
        ReferenceCase(
            name: "german ordinals (-g)",
            language: .other, germanOrdinals: true,
            knownTokens: [],
            input: "Am 3. Mai kam der 2. Gast. Es war 5. Das ist gut. Siehe 12.\n",
            expected: "Am\n3.\nMai\nkam\nder\n2.\nGast\n.\n\nEs\nwar\n5.\nDas\nist\ngut\n.\n\nSiehe\n12.\n\n"),
        ReferenceCase(
            name: "same text without -g",
            language: .other, germanOrdinals: false,
            knownTokens: [],
            input: "Am 3. Mai kam der 2. Gast. Es war 5. Das ist gut. Siehe 12.\n",
            expected: "Am\n3\n.\n\nMai\nkam\nder\n2\n.\n\nGast\n.\n\nEs\nwar\n5\n.\n\nDas\nist\ngut\n.\n\nSiehe\n12\n.\n\n\n"),
        ReferenceCase(
            name: "known tokens (-a)",
            language: .other, germanOrdinals: false,
            knownTokens: ["Dr.", "etc", "z.B.", "Mr."],
            input: "Dr. Meyer kam, etc. Siehe z.B. (Mr.) oder (etc.) Dr.\nNeuer Satz.\n",
            expected: "Dr.\nMeyer\nkam\n,\netc\n.\n\nSiehe\nz.B.\n(\nMr.\n)\noder\n(\netc\n.\n)\n\nDr.\nNeuer\nSatz\n.\n\n\n"),
        ReferenceCase(
            name: "whitespace, BOM, CRLF, no final newline",
            language: .other, germanOrdinals: false,
            knownTokens: [],
            input: "\u{FEFF}foo\u{00A0}bar.\r\nbaz?\n\n  qux!\u{3000}(x) ...",
            expected: "foo\nbar\n.\n\nbaz\n?\n\nqux\n!\n\n(\nx\n)\n...\n\n"),
        ReferenceCase(
            name: "punctuation clusters",
            language: .other, germanOrdinals: false,
            knownTokens: [],
            input: "Wait?!Really;yes. »Hello,« „Quote“ … a.)  b?). ,,x`` ''y'' [a] {b} 50% ¿Qué? ¡Sí!\n",
            expected: "Wait\n?\n\n!Really\n;\nyes\n.\n\n»\nHello\n,\n«\n„\nQuote\n“\n…\na.\n)\nb\n?\n\n)\n.\n\n,,\nx\n`\n`\n'\n'\ny\n''\n[\na\n]\n{\nb\n}\n50\n%\n¿\nQué\n?\n\n¡\nSí\n!\n\n\n"),
    ]
}
