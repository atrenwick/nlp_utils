//
//  UDStructures.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
//

import Foundation

// MARK: - Tokenizer output



struct Token : Identifiable {
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
    
    var conlluLine: String {
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel].joined(separator: "\t")
    }
    
    var conllRaw: String{
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel, "_","_"].joined(separator: "\t") //+ "\n"
    }
    var conllRawMultitag: String{
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel, col8,col9].joined(separator: "\t") //+ "\n"
    } // this includes NL parser outputs for col8,9, but the funct to make the ExportString doesn't call this prop.
    
    var asXML: String{
                """
                <w tokID=\"\(tokid)\"  form=\"\(form.xmlEscaped)\" lemma=\"\(lemma.xmlEscaped)\" upos=\"\(upos.xmlEscaped)\" xpos=\"\(xpos.xmlEscaped)\" feats=\"\(feats.xmlEscaped)\" head=\"\(head.xmlEscaped)\" deprel=\"\(deprel.xmlEscaped)\">\(form.xmlEscaped)</w>
                """
    }
}

struct Sentence : Identifiable {
    var id = UUID()
    let sentID: String
    let conllData: [Token]

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
    
    var sentIdAsMeta: String {
        // 1. Trim  leading and trailing  (\n, \r) with .newlines
        // 4. Prepend exact required header
        return "\n\n# sent_id = \(runSentIdRegexes)"
    }
    
    func makeXMLsent(exportFormat: ExportFormat) -> String {
        var xmlTokenElements: [String] = []
        let sentHeader = """
        <s id=\"\(runSentIdRegexes)\">
        """
        let sentFooter = """
            </s>
            """
        
        xmlTokenElements.append(sentHeader)
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

    var conll: String {
        var internalLineList: [String] = []
        internalLineList.append(sentIdAsMeta)
        for token in conllData{
            internalLineList.append(token.conllRaw)
        }
        return internalLineList.joined(separator: "\n")
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
        return HashableSentence(id: sentID, tokens: internalTokList)
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
        var lines: [ConllLineContent] = conllData.map { .row($0) }
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
                    tok.xpos, tok.feats, tok.head, tok.deprel,
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


struct HashableSentence: Hashable {
    // sentence as id + list of strings as input for parser
    let id: String
    let tokens: [String]
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



struct XmlHeaderAttribs{
    let xmlTitle: String
    let xmlAuthorName: String
    let lang: String
    let treebank: String
    let taggingDate: String
    let sourceFile: String
    let runID: String
}


struct RunOutput: Identifiable {
    var id = UUID()
    let sents: [Sentence]
    let sourceFileName: String
    let outputFileName: URL
    let lang: String
    let treebank : String
    let exportFormat: ExportFormat
    var unread: Bool = true
    
    var tokCount: Int {
        // reduce collection to single element : start at 0, add iteratively over elements
        sents.reduce(0) { $0 + $1.conllData.count }
    }
}



struct SaveReport {
    let savedURL: URL?
    let message: String
}

struct ExporterService {
    /// Writes processing output string directly to a user-selected folder URL
    static func exportDataToFile(
        exportContent: String,
        customName: String,
        targetFolderURL: URL,
        exportFormat: ExportFormat
        
    ) throws -> URL {
        let fileExtension = exportFormat.fileExtension
      
        print("step1 success")
        // 2. Format sanitized filename
        var safeName = customName.sanitizedFileName
        if !safeName.hasSuffix(".\(fileExtension)") {
                    safeName += ".\(fileExtension)"
                }
        print("step2 success")
        // 3. Construct destination path inside the chosen directory
        let destinationFileURL = targetFolderURL.appendingPathComponent(safeName)
        print("step3 success")
        // 4. Elevate security permissions for external directory write
        let gotAccess = targetFolderURL.startAccessingSecurityScopedResource()
        defer {
            if gotAccess {
                targetFolderURL.stopAccessingSecurityScopedResource()
                print("step4 success")
            }
        }
        
        // 5. Write
        try exportContent.write(to: destinationFileURL, atomically: true, encoding: .utf8)
        print("step5 success URL == \(destinationFileURL.path())")
        
        return destinationFileURL
    }
}
/* dealing with XMLconll docs as input */
struct XMLConllElement {
    let id: String  // send_id extracted with xmlparsing
    let blob: String // content of s.text == conll lines with sent id line added in by parser
}

//autoselect input type extension

struct TestToken: Identifiable, Hashable {
    let id: Int
    var form: String
    
}
