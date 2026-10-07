//
//  enumerations
//  Tagger
//
//  Created by Adam on 10/09/2026.
//

import Foundation
internal import UniformTypeIdentifiers


enum ConllLineContent {
    case row(Token)
    case blank
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

enum InputFileType: String, Identifiable, CaseIterable {
    var id: Self { self }
    
    case conll
    case txt
    case xml
    case xmlConll
    case manual
    
    var isTokenised: Bool {
        switch self {
        case .txt: return false
        case .conll, .xml, .xmlConll, .manual: return true
        
        }
    }
    var fileExtension: String{
        //extensionto use when writing
        switch self{
        case .conll: "conll"
        case .txt: "txt"
        case .xml, .xmlConll: "xml"
        case .manual : "_"
        }
    }
    var allowedReadExt: [String]{
        switch self{
        case .txt: return ["txt","TXT"]
        case .conll: return ["conll", "conllu", "txt"]
        case .xml, .xmlConll, .manual: return ["xml", "XML"]
        }
    }
    
    var utType: UTType{
        switch self {
        case .conll, .manual, .txt: return .plainText
        case .xml, .xmlConll: return UTType(filenameExtension: "xml") ?? .plainText
        }
    }
    
}

enum Language: String, CaseIterable, Identifiable {
    // uppercase lang code as used in file paths
    case EN
    case FR
    case DE
    case ANG
    case FRM
    case FRO
    
    var id: Self { self }
    
    // Readable label for Language
    var displayName: String {
        switch self {
        case .EN: return "en"
        case .FR: return "fr"
        case .DE: return "de"
        case .ANG: return "ang"
        case .FRM: return "frm"
        case .FRO: return "fro"
        }
    }
    
    var defaultTB: Treebank {
        switch self {
        case .EN: return .enTB1
        case .ANG: return .angTB1
        case .FR: return .frTB1
        case .DE: return .deTB1
        case .FRO: return .froTB1
        case .FRM: return .frmTB1
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
        case frmTB1 = "frm_profiterole"
        case froTB1 = "fro_profiterole"
        
        var id: String { rawValue }
        
        var short: String {
            // RHS of model files and Picker strings
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
            case .frmTB1: return "profiterole"
            case .froTB1: return "profiterole"
            }
        }
    }
    
    // Returns ONLY the models valid for this language
    var availableTBs: [Treebank] {
        switch self {
        case .EN: return [.enTB1, .enTB2, .enTB3]
        case .FR:  return [.frTB1, .frTB2, .frTB3]
        case .DE:  return [.deTB1, .deTB2]
        case .ANG: return [.angTB1]
        case .FRM: return [.frmTB1]
        case .FRO: return [.froTB1]
        }
    }
}


enum ParseProcessingError: LocalizedError{
    case missingURL
    case parserCreationError
    case xmlParserFailure(line: Int, reason: String)
    case noSentencesLoaded
    case retokenisationError
    case noRunOutput
    case ConllParsingError(line: String, filename:String)
    case ReadFromSandboxError
    case ConllLineIdentificationError
    case conllChunkToLineError
    case makeConllLinesFromURLError
    case makeExportContentError
    
    var errorDescription: String? {
        switch self{
        case .noRunOutput:
            return "No run output to return"
        case .missingURL:
            return "No URL provided"
        case .noSentencesLoaded:
            return "No sentences found when switching on inputFileTYpe"
        case .parserCreationError:
            return "Couldn't create XML parser from URL"
        case .xmlParserFailure:
            return "Unknown XML parsing error with XML parser + delegate"
        case .retokenisationError:
            return "Error retokenising: no sentences found"
        case .ReadFromSandboxError:
            return "Error reading the file from the sandbox"
        case .ConllParsingError(let lineNumber, let filename):
            return "Error parsing conll lines : 10 fields not found in file \(filename) line \(lineNumber)"
        case .ConllLineIdentificationError:
            return "Error getting finding sentence chunks in conll input"
        case .makeConllLinesFromURLError:
            return "Error in makeConllLinesFromURL function"
        case .conllChunkToLineError:
            return "Error in conllChunkToLineError function"
        case .makeExportContentError:
            return "Error in makeExportContent function"
        }
    }
}


enum PipelineStep: Int, CaseIterable, Identifiable, Comparable {
    // RawValue type (Int) links each case to an integer (1, 2, 3, 4).
    // Comparable conformance allows using <, >, <=, >= on enum cases.
    // step1 is tokenisation, and is handled with diff pipe
    case step2 = 2
    case step3 = 3
    case step4 = 4
    case step5 = 5
    
    // raw value = id, to conform to Identifiable
    var id: Int { rawValue }
    
    // Computed property: evaluates 'self' on demand and returns the matching  string
    var title: String {
        switch self {
        case .step2: return "2. POS tagging"
        case .step3: return "3. Lemmatisation"
        case .step4: return "4. Feats"
        case .step5: return "5. DepParse"
        }
    }
    // required for Comparable : Swift expects this to build other comparison operattions
    static func < (lhs: PipelineStep, rhs: PipelineStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum RetokenisationType: String, Identifiable, CaseIterable{
    var id: Self {self}
    case predict = "Predict"
    case manual = "Manual"
    case rule = "Rule"
    case skip = "skip" // special case for txt parsed from raw file - is already Hashable, so skip by toggling value
    }

enum SentencizingMethod: String, Identifiable, CaseIterable {
    var id: Self {self}
    case nlSentencizer
    case custom
    }

enum TokenizingMethod : String, Identifiable, CaseIterable{
    var id: Self {self}
    case custom = "Custom"
    case nltokeniser = "NLTokenizer"
    case trained = "Trained"
    case manual = "Manual"
    case skip = "Skip"
}

