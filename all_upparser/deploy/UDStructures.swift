//
//  UDStructures.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
//

import Foundation

// MARK: - Tokenizer output
struct TokenisedSentence: Hashable {
    let id: String
    let tokens: [String]
}

enum LanguageCode: String, CaseIterable, Identifiable {
    var id: Self {self}
    case FR
    case EN
}



struct UDToken : Identifiable {
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
    /// Tab-separated, in CoNLL-U column order (ID FORM LEMMA UPOS XPOS FEATS HEAD DEPREL).
    var conlluLine: String {
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel].joined(separator: "\t")
    }
    
    var conllRaw: String{
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel, "_","_"].joined(separator: "\t") //+ "\n"
    }
}


struct ConllSent : Identifiable {
    var id = UUID()
    let sentID: String
    let conllData: [UDToken]
    
//    var sentIdaAsMeta: String{
//        var addLBs: Bool = false
//        var lbreaks: String = ""
//        var addConllMetaHeader: Bool = false
//        var cHeader: String = ""
//        var currentSentID: String = sentID
//        if currentSentID.hasPrefix("\n\n") != true{
//            addLBs = true
//            lbreaks = "\n\n"
//        }
//        if currentSentID.contains("# sent_id = ") != true {
//            addConllMetaHeader = true
//            cHeader = "# sent_id = "
//        }
//        
//        //if starts with s lb, no add
//        currentSentID = "\(lbreaks)\(cHeader)\(sentID)"
//        currentSentID = currentSentID.replacing(#/\n{3,}/#, with: "\n\n")
//        return currentSentID
//    }
    var sentIdAsMeta: String {
        // 1. Trim ONLY leading and trailing newlines (\n, \r), preserving spaces in "foo bar"
        var content = sentID.trimmingCharacters(in: .newlines)
        
        // 2. Remove existing header variants if already present
        let pattern = #"^\s*#\s*sent_id\s*=\s*"#
            
            if let range = content.range(of: pattern, options: .regularExpression) {
                content.removeSubrange(range)
            }
        // 3. Re-trim ONLY newlines from the payload before applying header
        content = content.trimmingCharacters(in: .newlines)
        // 4. Prepend exact required header
        return "\n\n# sent_id = \(content)"
    }
    
    //TODO: add var to send to XML
    
    
    
    
    
    
    var conllSentRaw: String {
        // get raw conll for printing
        var internalLineList: [String] = []
        internalLineList.append(sentIdAsMeta)
        for udToken in conllData{
            internalLineList.append(udToken.conllRaw)
        }
        return internalLineList.joined(separator: "\n")
    }
    
    var conllSentTidy: String {
        var internalLineList: [String] = []
        for item in formatTidy(){
            internalLineList.append(item)
        }
        return internalLineList.joined(separator: "\n")
    }
        


    var sentAsTokenisedSentence: TokenisedSentence{
        //convert to TokenisedSentence for parsing
        var internalTokList: [String] = []
        for token in conllData{
            internalTokList.append(token.form)
        }
        return TokenisedSentence(id: sentID, tokens: internalTokList)
    }
    
    
    func formatRaw() -> [String]{
        
        var lines: [OutputLine] = conllData.map { .row($0) }
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
        var lines: [OutputLine] = conllData.map { .row($0) }
        //lines.append(.blank)

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


struct CoNLLDoc {
    //this if output date re calculated properties, methods
    var id = UUID()
    let sentences:[ConllSent]
    
    var docAsRaw: String{
        var internalList: [String] = []
        for sentence in sentences {
            internalList.append(sentence.conllSentRaw)
            internalList.append("\n")
        }
        
        return internalList.joined(separator: "\n")
    }
}

func printFromConllSents(outsents: [ConllSent]) throws -> URL{
    
    let mySents: [ConllSent] = outsents
    let fileName = "string_dump_\(Int(Date().timeIntervalSince1970 * 1_000_000_000))_special.conllu"
    let newUrl: URL = URL(fileURLWithPath: "/Volumes/Kappa/Xcode/parses/\(fileName)")
    
    var myLines: [String] = []
    var atStart: Bool = true
    for sent in mySents {
        if atStart {
            atStart = false
            let pattern =  #"^\n{2}"#
            var firstSent = sent.conllSentRaw
            print(firstSent.count)
                if let range = firstSent.range(of: pattern, options: .regularExpression) {
                    firstSent.removeSubrange(range)
                }
            myLines.append(firstSent)
            print("Appended length = \(firstSent.count)")
        } else {
            myLines.append(sent.conllSentRaw)
        }
    }
    for sent in mySents {
        myLines.append(sent.conllSentTidy)
    }

    
    let content = myLines.joined(separator: "")
    try content.write(to: newUrl, atomically: true, encoding: .utf8)
    print("Saved CoNLL dump to: \(newUrl.path)")

    return newUrl
        
        
}
