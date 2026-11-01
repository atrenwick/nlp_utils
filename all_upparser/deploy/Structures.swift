//
//  Structures.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
//

import Foundation
import CoreML

struct AdditionalExportParams{
    let exportFormat: ExportFormat
    let includeConllSentText: Bool
}

struct BuiltSentHolder: Identifiable, Hashable{
    var id = UUID()
    var tempToks: [TempToken]
    
    func toHashableSent(tempToks: [TempToken]) -> HashableSentence? {
        guard tempToks.count > 0 else {return nil }
        return tempToks.makeHashableSentFromTestToks()
    }
    
    func toShowString(tempToks: [TempToken])-> AttributedString {
        guard tempToks.count > 0 else {return "error1" }
        if let hashableSent = tempToks.makeHashableSentFromTestToks(){
            return TokenisationWorkflow.markupTokenisationInSent(hashableSent: hashableSent)
        } else { return "error2" }
    }
}

struct ConfigurationRules {
    // Define which languages are available per architecture
    static func availableLanguages(for architecture: ModelArchitecture) -> [Language] {
        switch architecture {
        case .camembert, .roberta:
            return [.FR]
        case .cnnBiLSTM:
            return [.EN, .FR, .ANG, .DE, .FRM, .FRO].sorted {$0.rawValue < $1.rawValue}
        case .distilbert:
            return [.EN, .FR, .ANG, .DE, .FRM, .FRO].sorted {$0.rawValue < $1.rawValue}
        }
    }
    
    // Define which treebanks are available based on the language & architecture combination
    static func availableTreebanks(for architecture: ModelArchitecture, language: Language) -> [Language.Treebank] {
        switch architecture {
        case .cnnBiLSTM:
            switch language {
                case .EN: return [.enTB1, .enTB2, .enTB3]
                case .FR: return [.frTB1, .frTB2, .frTB3]
                case .DE:  return [.deTB1, .deTB2]
                case .ANG: return [.angTB1]
                case .FRM: return [.frmTB1]
                case .FRO: return [.froTB1]
            }
        case .camembert, .roberta:
            switch language {
            case .FR: return [.frTB1]
            default : return [.frTB1]
            }
            
        case .distilbert:
            switch language {
            case .FR: return [.frTB1, .frTB2, .frTB3]
            case .DE: return [.deTB1]
            case .ANG: return [.angTB1]
            case .EN: return [.enTB1, .enTB2]
            case .FRM: return [.frmTB1]
            case .FRO: return [.froTB1]
            }
        }
    }
}

struct Document {
    var id = UUID()
    let sentences:[Sentence]
    
    var docAsRaw: String{
        var internalList: [String] = []
        for sentence in sentences {
            internalList.append(sentence.conll)
            internalList.append("\n")
        }
        return internalList.joined(separator: "\n")
    }
}

struct HashableSentence: Hashable {
    // sentence as id + list of strings as input for parser
    let id: String
    let tokens: [String]
    let conllMetas: [String]
    var detokenised: String {
        tokens.joined(separator: " ")
    }
}

struct OnSentResult: Identifiable {
    var id = UUID()
    let sentence: HashableSentence // input sent
    var subtokCount: Int = -1
    let resultType: OnSentResultType
    let decoded: [Token]
}

struct OutputError: Identifiable {
    var id = UUID()
    let sentence: HashableSentence
    let tokCount: Int
    let subtokCount: Int
    let errorType: OnSentResultType
    }

struct OutputFileListHelper: Identifiable{
    let id: UUID
    let runID: String
    let url: URL
}

struct RegexLangPatternToLangMap: Identifiable{
    var id = UUID()
    let string: String
    let langValue: Language
    
    var asRegex: Regex<Substring>{
        try! Regex(string)
    }
}

struct RunData: Identifiable, Codable {
    var id = UUID()
    let runID: String
    let sents: [Sentence]
    let exportContent: String
    var tokCount: Int {
        // reduce collection to single element : start at 0, add iteratively over elements
        sents.reduce(0) { $0 + $1.conllData.count }
    }
}

struct RunFileWrapper: Decodable {
    let id: UUID
    let runMetas: RunMetas
}

struct RunMetas: Identifiable, Codable {
    let id = UUID()
    let runID: String
    let exportFormat: ExportFormat
    let includeConllSentIdLine: Bool
    let includeConllSentText: Bool
    let inputFileType: InputFileType
    let lang: String
    let maxPipelineStep: PipelineStep
    let message: String
    let outputFileName: String
    let processedCount: Int
    let runResentenciser: Bool
    let runRetokeniser: Bool
    let safeHeaderAttribs: XmlHeaderAttribs
    let savedURL: URL?
    let selectedRetokenisationType: RetokenisationType
    let sentencizingMethod: SentencizingMethod
    let sourceFileName: String
    let sourceFileURL: URL?
    let targetFolderURL: URL?
    let tokenizingMethod: TokenizingMethod
    let totalCount: Int
    let treebank : String
    var unread: Bool = true
    
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "SavedData")
        }
    }
}

struct RunOutput: Identifiable, Codable {
    var id = UUID()
    let runID: String
    let runData: RunData
    var runMetas: RunMetas
}

struct RunSelectorHelper{
    let runMetas: RunMetas
    let jsonFile: URL
}

struct SandboxImporter {
    static func importToSandbox(from externalURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let targetURL = docsDir.appendingPathComponent(externalURL.lastPathComponent)
        
        // Remove old instance if it exists at target path
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        // Copy the file to sandbox
        try fileManager.copyItem(at: externalURL, to: targetURL)
        
        return targetURL
    }
}

struct Sentence : Identifiable, Codable {
    var id = UUID()
    let sentID: String
    let conllData: [Token]
    let conllMetas: [String]

    var tokCount: Int {
        conllData.count
    }
    var runSentIdRegexes: String{
        var content = sentID.trimmingCharacters(in: .newlines)
        // 2. Remove existing header if any
        let pattern = #"^\s*#\s*sent_id\s*=\s*"#
            if let range = content.range(of: pattern, options: .regularExpression) {
                content.removeSubrange(range)
            }
        // 3. Re-trim ONLY newlines from the payload before applying header
        content = content.trimmingCharacters(in: .newlines)
        return content
    }
    
    var conllMetaTextLine: String {
        var internalList: [String] = ["# sent_text = "]
        internalList.append(contentsOf: conllData.map {$0.form})
        return internalList.joined(separator: " ")
    }
    
    var sentIdAsMeta: String {
        return "\n\n# sent_id = \(runSentIdRegexes)"
    }
    
    func makeXMLsent(exportFormat: ExportFormat, includeConllSentText: Bool) -> String {
        var xmlTokenElements: [String] = []
        let sentHeader = """
        <s id=\"\(runSentIdRegexes)\">
        """
        let sentFooter = """
            </s>
            """
        
        xmlTokenElements.append(sentHeader)
        if includeConllSentText {
            xmlTokenElements.append("# sent_id = \(runSentIdRegexes)")
            xmlTokenElements.append(conllMetaTextLine)
        }

        switch exportFormat{
        case .xml:
            xmlTokenElements.append(conllData.makeSentenceXML())
        case .xmlConll:
            xmlTokenElements.append(conllData.makeSentenceXMLconll())
        default:
            return ""
        }
        xmlTokenElements.append(sentFooter)
        return xmlTokenElements.joined(separator: "\n")
    }
    func makeConll(sentInMeta: Bool = true) -> String {
        var lineStore: [String] = []
        lineStore.append(sentIdAsMeta)

        if sentInMeta {
            var sentTextLine = ["# sent = "]
            sentTextLine.append(contentsOf: conllData.map {$0.form} )
            lineStore.append(sentTextLine.joined(separator: " "))
        }
        lineStore.append(contentsOf: conllData.map {$0.conllRaw})
        return lineStore.joined(separator: "\n")
    }
    var conll: String {
        var conllString = ["\n# sent_id = \(sentID)"]
        conllString.append(contentsOf: conllData.map {$0.conlluLine} )
        return conllString.joined(separator: "\n")
    }
    
    var conllTidy: String {
        var internalLineList: [String] = []
        for item in formatTidy(){
            internalLineList.append(item)
        }
        return internalLineList.joined(separator: "\n")
    }

    var hashableSentence: HashableSentence{
        //convert to TokenisedSentence for parsing
        var internalTokList: [String] = []
        for token in conllData{
            internalTokList.append(token.form)
        }
        return HashableSentence(id: sentID, tokens: internalTokList, conllMetas: self.conllMetas)
    }
    
    func formatRaw() -> [String]{
        var lines: [ConllLineContent] = conllData.map { .row($0) }
        lines.append(.blank)
        var result = lines.map { line in
            switch line {
            case .row(let tok): return tok.conllRaw
            case .blank: return ""
            }
        }
        result.insert("\n\(sentID)", at: 0)
        return result
    }

    /// Use string count to column-align rows of each sent  independently
    func formatTidy() -> [String] {
        //get lines, add blank for end
        let lines: [ConllLineContent] = conllData.map { .row($0) }
        var result: [String] = []
        result.append(sentIdAsMeta)
        var currentRows: [[String]] = []
        
        func flushSentence() {
            // calculate how to make tidy cols, make tidy cols
            guard let columnCount = currentRows.first?.count else { return }
            var widths = Array(repeating: 0, count: columnCount)
            for row in currentRows {
                for (i, field) in row.enumerated() {
                    widths[i] = max(widths[i], field.count)
                }
            }
            for row in currentRows {
                let padded = row.enumerated().map { i, field in
                    field.padding(toLength: widths[i], withPad: " ", startingAt: 0)
                }
                result.append(padded.joined(separator: "  "))
            }
            currentRows = []
        }

        //process toks, flush, append
        for line in lines {
            switch line {
            case .row(let tok):
                currentRows.append([
                    String(tok.tokid), tok.form, tok.lemma, tok.upos,
                    tok.xpos, tok.feats, tok.head, tok.deprel, tok.col8, tok.col9
                ])
            case .blank:
                flushSentence()
                result.append("")
            }
        }
        flushSentence() // in case the input didn't end with a trailing .blank
        return result
    }
}

struct TaggerRawOutput {
    // for CNN-BiLSTM model
    /// Holds the raw tensors from 1 tagger_parser model call for 1 sent
    ///`seqLen` includes the synthetic ROOT index 0, so real words are indices 1,2....<seqLen.
    let sentence: HashableSentence
    let seqLen: Int
    let uposLogits: MLMultiArray
    let xposLogits: MLMultiArray
    let featsLogits: MLMultiArray
    let ruleLemmaLogits: MLMultiArray //rulebase lemma logits
    let decodedLemmas: [String]
    let arcLogits: MLMultiArray
    let labelLogits: MLMultiArray
}

// struct for manually tokenised, modified inputs, before conversion to Token
struct TempToken: Identifiable, Hashable {
    var id = UUID()
    var form: String
}

struct Token : Identifiable, Codable {
    var id = UUID()
    let tokid: Int
    let form: String
    let lemma: String
    let upos: String
    let xpos: String
    let feats: String
    let head: String
    let deprel: String
    let col8: String
    let col9: String
    let subTokens: [String]?
    
    var conlluLine: String {
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel, col8, col9].joined(separator: "\t")
    }
    
    var conllRaw: String{
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel, col8,col9].joined(separator: "\t") //+ "\n"
    } // this includes NL parser outputs for col8,9, but the funct to make the ExportString doesn't call this prop.
    
    var escapedUnwrappedSubtoks: String {
        if let theseItems = subTokens{
            return theseItems.joined(separator: "//").xmlEscaped
        } else {
            return col9.xmlEscaped
        }
    }
    
    var asXML: String{
                """
                <w tokID=\"\(tokid)\"  form=\"\(form.xmlEscaped)\" lemma=\"\(lemma.xmlEscaped)\" upos=\"\(upos.xmlEscaped)\" xpos=\"\(xpos.xmlEscaped)\" feats=\"\(feats.xmlEscaped)\" head=\"\(head.xmlEscaped)\" deprel=\"\(deprel.xmlEscaped)\" secLem=\"\(col8.xmlEscaped)\" subtoks=\"\(escapedUnwrappedSubtoks)\">\(form.xmlEscaped)</w>
                """
    }
}
// MARK: - Vocabulary
//structure to decode the vocab data JSON file
struct VocabData: Decodable {
    let itos: [String]
    let pad: String
    let unk: String
}

/* dealing with XMLconll docs as input */
struct XMLConllElement {
    let id: String  // send_id extracted with xmlparsing
    let blob: String // content of s.text == conll lines with sent id line added in by parser
}

struct XmlHeaderAttribs : Codable{
    // get lengths for sequences, subtokens, defaulting to 1 and, for latter, -99 if CNN-BiLSTM, -1 if error, or, if supplied value, this value
    var xmlTitle: String
    var xmlAuthorName: String
    var lang: String
    var treebank: String
    var taggingDate: String
    var sourceFile: String
    var runID: String
    var maxPipelineStep: String
    var modelArchitecture: String
    var runRetokeniser: String
    var tokenizingMethod: String
    var sentencizingMethod: String
    var maxWords: String
    var maxSeqLen: String
    init(
        xmlTitle: String? = nil,
        xmlAuthorName: String? = nil,
        lang: String? = nil,
        treebank: String? = nil,
        taggingDate: String? = nil,
        sourceFile: String? = nil,
        runID: String? = nil,
        maxPipelineStep: String? = nil,
        modelArchitecture: ModelArchitecture? = nil,
        runRetokeniser: String? = nil,
        tokenizingMethod: String? = nil,
        sentencizingMethod: String? = nil,
        maxWords: String? = nil,
        maxSeqLen: String? = nil
    ) {
        self.xmlTitle = xmlTitle ?? "xmlTitle"
        self.xmlAuthorName = xmlAuthorName ?? "xmlAuthorName"
        self.lang = lang ?? "lang"
        self.treebank = treebank ?? "treebank"
        self.taggingDate = taggingDate ?? "taggingDate"
        self.sourceFile = sourceFile ?? "sourceFile"
        self.runID = runID ?? "runID"
        self.maxPipelineStep = maxPipelineStep ?? "maxPipelineStep"
        self.modelArchitecture = modelArchitecture?.rawValue ?? "modelArchitecture"
        self.runRetokeniser = runRetokeniser ?? "runRetokeniser"
        self.tokenizingMethod = tokenizingMethod ?? "tokenizingMethod"
        self.sentencizingMethod = sentencizingMethod ?? "sentencizingMethod"
        self.maxWords = maxWords ?? "0"
        self.maxSeqLen = modelArchitecture?.rawValue == "distilbert" ? maxSeqLen ?? "ERR" : "NA"
    }
}
