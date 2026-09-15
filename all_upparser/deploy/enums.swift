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
    case ANG
    
    var id: Self { self }
    
    // Readable label for Language
    var displayName: String {
        switch self {
        case .EN: return "en"
        case .FR: return "fr"
        case .DE: return "de"
        case .ANG: return "ang"
        }
    }
    
    // Nested enum for all available models
    enum Treebank: String, CaseIterable, Identifiable {
        case enTB1 = "en_ewt"
        case enTB2 = "en_gum"
        case enTB3 = "en_lines"
        case frTB1 = "fr_gsd"
        case frTB2 = "fr_sequoia"
        case frTB3 = "fr_rhapsodie"
        case deTB1 = "de_gsd"
        case deTB2 = "de_hdt"
        case angTB1 = "ang_oedt"
        
        var id: String { rawValue }
        
        var short: String {
            switch self {
            case .enTB1: return "ewt"
            case .enTB2: return "gum"
            case .enTB3: return "lines"
            case .frTB1: return "gsd"
            case .frTB2: return "sequoia"
            case .frTB3: return "rhapsodie"
            case .deTB1: return "gsd"
            case .deTB2: return "hdt"
            case .angTB1: return "oedt"

            }
        }
    }
    
    // Returns ONLY the models valid for this language
    var availableTBs: [Treebank] {
        switch self {
        case .EN: return [.enTB1, .enTB2, .enTB3]
        case .FR:  return [.frTB1, .frTB2, .frTB3]
        case .DE:  return [.deTB1, .deTB2]
        case.ANG: return [.angTB1]
        }
    }
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


// choose languages supported ::: LanguageCode enum
enum OutputTarget: String, CaseIterable, Identifiable{
    var id: Self {self}
    case Export
    case ViewOnly
}



enum XMLOutputType:  String, CaseIterable, Identifiable {
    var id: Self {self}
    case xml
    case xmlConll
}


enum ExportFormat: String, CaseIterable, Identifiable{
    var id: Self {self}
    case xml
    case xmlConll
    case conll
    case conllTidy
    case conllTxt
    
    var fileExtension: String{
        switch self{
        case .xml: "xml"
        case .xmlConll : "xml"
        case .conll: "conll"
        case .conllTidy: "conll"
        case .conllTxt: "txt"
        }
    }
}

struct ExporterService {
    //TODO: make this take an arg for export format
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
    func generateExportTextTidy() -> String {
        return self.map { $0.conllSentTidy }.joined(separator: "\n")
    }
}

extension Sequence where Element == UDToken {
    /// Combines calculated properties across all structures
    func makeSentenceXML() -> String {
        return self.map { $0.asXML }.joined(separator: "\n")
    }
}

extension Sequence where Element == UDToken {
    /// Combines calculated properties across all structures
    func makeSentenceXMLconll() -> String {
        return self.map { $0.conllRaw }.joined(separator: "\n")
    }
}

struct RunOutput: Identifiable {
    var id = UUID()
    let sents: [ConllSent]
    let sourceFileName: URL
    let lang: String
    let treebank : String
    
//    var tokCount: Int {
//        var total: Int = 0
//        for sent in sents{
//            total += sent.conllData.count
//        }
//        return total
//    }
    var tokCount: Int {
        // reduce collection to single element : start at 0, add iteratively over elements
        sents.reduce(0) { $0 + $1.conllData.count }
    }
}
