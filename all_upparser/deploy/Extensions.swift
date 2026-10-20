//
//  Extensions.swift
//  Tagger
//
//  Created by Adam on 14/09/2026.
//

import Foundation

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

extension PipelineSettingsView {
    // 1. Array of missing configuration items
    var missingRequirements: [String] {
        var missing: [String] = []
        
        // Rule 1: Check input file exists in sandbox
        if fileContainerModel.localSandboxFileURL == nil && myConfig.inputConfig.inputFileType != .manual{
            missing.append("Input File")
        }

        let ext = fileContainerModel.localSandboxFileURL?.pathExtension ?? "nil"
        if  myConfig.inputConfig.inputFileType.allowedReadExt.contains(ext) == false  && myConfig.inputConfig.inputFileType != .manual {
            missing.append("extension-InputType Mismatch")
        }
        
        if myConfig.inputConfig.inputFileType == .manual && builtSents.count == 0 {
            missing.append("No built sents found")
        }
        
        // Rule 2: Check custom output filename is typed
        if myConfig.exportConfig.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Output Filename")
        }
        
        // Rule 3: Check target folder (or destination setting)
        if myConfig.exportConfig.targetFolderURL == nil {
            missing.append("Export Directory")
        }
        
        return missing
    }

    // 2. Boolean check for the .disabled() modifier
    var isPipelineReady: Bool {
        return missingRequirements.isEmpty
    }

    // 3. User-friendly warning message
    var missingRequirementsMessage: String {
        guard !missingRequirements.isEmpty else { return "" }
        
        if missingRequirements.count == 1 {
            return "Set: \(missingRequirements[0])"
        } else {
            // Lists items cleanly: "Missing required settings: Input File, Output Filename, Export Directory"
            return "Missing required settings: \(missingRequirements.joined(separator: ", "))"
        }
    }
}

protocol NLPPipeline{
    func runOnSentence(_ sentence: HashableSentence, myConfig: TaggerConfig) throws -> [Token]
}

extension NLPPipeline{
    func tokenize(_ naughtyString: String) -> HashableSentence{
        let input = naughtyString
        let intermediate = input.split(separator: " ")
        let output = intermediate.map {String($0)}
        let outputSent = HashableSentence(id: "e2", tokens: output, conllMetas: [])
        print("this should't have been callable…")
        return outputSent
    }

}
