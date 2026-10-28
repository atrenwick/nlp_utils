//
//  Extensions.swift
//  Tagger
//
//  Created by Adam on 14/09/2026.
//

import Foundation
import SwiftUI
internal import UniformTypeIdentifiers


//MARK: string extensions

extension String {
    var isLower: Bool {
        self == self.lowercased() && self != self.uppercased()
    }

    var sanitizedFileName: String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\":<>")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = self.components(separatedBy: invalidCharacters).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Export_Output" : trimmed
    }
    var xmlEscaped: String {
        var result = self
        result = result.replacingOccurrences(of: "&", with: "&amp;")   // must be first
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        return result
    }

    var asTempToken: TempToken {
            return TempToken(form: String(self))
        }
}

//MARK: sequence extensions extensions
extension Sequence where Element == Sentence {
    /// Combines calculated properties across all structures
    func generateExportText() -> String {
        return self.map { $0.conll}.joined(separator: "\n")
    }
    func generateExportTextTidy() -> String {
        return self.map { $0.conllTidy }.joined(separator: "\n")
    }
    func generateTokCount() -> String {
        String(self.reduce(0) {$0 + $1.tokCount})
    }
    
    func generateXMLsentences() -> String{
        return self.map { $0.makeXMLsent(exportFormat: .xml, includeConllSentText: false)} .joined(separator: "\n")
    }
}

extension Sequence where Element == Token {
    /// Combines calculated properties across all structures
    func makeSentenceXML() -> String {
        return self.map { $0.asXML }.joined(separator: "\n")
    }
    func makeSentenceXMLconll() -> String {
        return self.map { $0.conllRaw }.joined(separator: "\n")
    }
}

// use collection as need to get .Count
extension Collection where Element == TempToken {
    
    func makeHashableSentFromTestToks()-> HashableSentence?{
        guard self.count > 0 else {return nil}
        var keepTokens: [String] = []
        for item in self {
            if item.form != ""{
                keepTokens.append(item.form)
            }
        }
        let returnObject = HashableSentence(id: UUID().uuidString, tokens: keepTokens, conllMetas: [])
        for x in returnObject.tokens{
            print(x)
        }
        return returnObject
    }
}


extension URL {
    var normalizedDir: URL {
        standardizedFileURL.resolvingSymlinksInPath()
    }
}
