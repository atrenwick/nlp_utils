//
//  Structures.swift
//  Tagger
//
//  Created by Adam on 10/09/2026.
//

import Foundation

enum Language: String, CaseIterable, Identifiable {
    case EN
    case FR
    case DE
    
    var id: Self { self }
    
    // Readable label for Language
    var displayName: String {
        switch self {
        case .EN: return "en"
        case .FR: return "fr"
        case .DE: return "de"
        }
    }
    
    // Nested enum for all available models
    enum Treebank: String, CaseIterable, Identifiable {
        case enTB1 = "en_ewt"
        case enTB2 = "en_gum"
        case frTB1 = "fr_gsd"
        case frTB2 = "fr_sequoia"
        case deTB1 = "de_gsd"
        case deTB2 = "de_hdt"
        
        var id: String { rawValue }
        
        var short: String {
            switch self {
            case .enTB1: return "ewt"
            case .enTB2: return "gum"
            case .frTB1: return "gsd"
            case .frTB2: return "sequoia"
            case .deTB1: return "gsd"
            case .deTB2: return "hdt"
            }
        }
    }
    
    // Returns ONLY the models valid for this language
    var availableTBs: [Treebank] {
        switch self {
        case .EN: return [.enTB1, .enTB2]
        case .FR:  return [.frTB1, .frTB2]
        case .DE:  return [.deTB1, .deTB2]
        }
    }
}


// choose languages supported ::: LanguageCode enum
enum OutputTarget: String, CaseIterable, Identifiable{
    var id: Self {self}
    case Export
    case ViewOnly
}

enum InputFileType: String, Identifiable, CaseIterable {
    case conll
    case txt
    case xml
    
    var id: Self { self }

    var isTokenised: Bool {
        switch self {
        case .conll: return true
        case .txt: return false
        case .xml: return true
        }
    }
}



struct ExporterService {
    
    /// Writes processing output string directly to a user-selected folder URL
    static func exportDataToFile(
        items: [ConllSent],
        customName: String,
        targetFolderURL: URL//,
        
    ) throws -> URL {
        let fileExtension: String = "conll"
        print("exporter called")
        // 1. Prepare export text string
        let exportContent = items.generateExportText()
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



extension String {
    var sanitizedFileName: String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\":<>")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = self.components(separatedBy: invalidCharacters).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Export_Output" : trimmed
    }
}

extension Sequence where Element == ConllSent {
    /// Combines calculated properties across all structures
    func generateExportText() -> String {
        return self.map { $0.conllSentRaw }.joined(separator: "\n")
    }
}


