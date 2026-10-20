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

enum EosApproach{
    case current
    case next
}

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
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

enum InputFileType: String, Identifiable, CaseIterable, Codable {
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

enum InsertPosition : String, Identifiable, CaseIterable{
    var id: Self {self}
    case before
    case after
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

enum LemmaSource: String, CaseIterable, Identifiable{
    var id: Self {self}
    case rule
    case hybrid
    
    var displayName: String {
        switch self {
        case .rule:
            return "Rule"
        case .hybrid:
            return "Hybrid"
        }
    }
    
}

enum ModelArchitecture: String, CaseIterable, Identifiable{
    var id: Self { self }
    case distilbert
    case cnnBiLSTM
    var displayName: String{
        switch self{
        case .distilbert: return "DistilBERT"
        case .cnnBiLSTM: return "CNN-BiLSTM"
        }
    }
    
}

enum PipelineError: LocalizedError{

    
    case architectureConflict
    case badTempTokens
    case configFileLoadError(name: String)
    case conllParsingError(line: String, filename:String)
    case conllLineIdentificationError
    case conllChunkToLineError
    case emptyInput
    case fileLoadError
    case fileNotInBundle
    case fileSaveError(filename: String)
    case inputFileFormatChoiceError
    case invalidLevel(Int)
    case invalidModelInputs(String)
    case languageMethodConflict(language: Language)
    case lemmatizationFailed(String)
    case makeConllLinesFromURLError
    case makeExportContentError
    case missingResource(String)
    case missingURL
    case modelLoadFailed(Error)
    case noRunOutput
    case noSentencesLoaded
    case outputFolderCreationError
    case packageLoadFailed(String)
    case parserCreationError(file: URL)
    case predictionFailed(Error)
    case predictionFailedAtLogits(String)
    case resourceMissing(String)
    case readFromSandboxError
    case retokenisationError
    case tokenizationFail(String)
    case unexpectedOutput(String)
    case utf8DecodeError
    case xmlParserFailure(line: Int, reason: String)
    
    var errorDescription: String? {
        switch self{
            
        case .architectureConflict:
            return "conflict between architecture and available models"
        case .badTempTokens:
            return "Error makiing hashable sentence from temp tokens"
        case .configFileLoadError(let filename):
            return "Failed to load file config file \(filename)"
        case .conllParsingError(let lineNumber, let filename):
            return "Error parsing conll lines : 10 fields not found in file \(filename) line \(lineNumber)"
        case .conllLineIdentificationError:
            return "Error getting finding sentence chunks in conll input"
        case .conllChunkToLineError:
            return "Error in conllChunkToLineError function"
        case .emptyInput:
            return "There are no words to annotate"
        case .fileLoadError:
            return "Failed to load file"
        case .fileSaveError(let filename):
            return "Failed to save to file \(filename)"
        case .fileNotInBundle:
            return "File not in bundle"
        case .inputFileFormatChoiceError:
            return "Not an XML format"
        case .invalidLevel(let level):
            return "Invalid pipeline level \(level): must be between 1 and 5."
        case .invalidModelInputs(let detail):
            return "Unexpected model inputs: \(detail)"
        case .languageMethodConflict(let language):
            return "Language \(language.rawValue) cannot be used with naive tokenisation"
        case .lemmatizationFailed(let msg):
            return "Lemmatization failed: \(msg)"
        case .makeConllLinesFromURLError:
            return "Error in makeConllLinesFromURL function"
        case .makeExportContentError:
            return "Error in makeExportContent function"
        case .missingResource(let name):
            return "Missing bundled resource: \(name). Did you add it to the app target?"
        case .missingURL:
            return "No URL provided"
        case .modelLoadFailed(let error):
            return "Couldn't load the model: \(error.localizedDescription)"
        case .noRunOutput:
            return "No run output to return"
        case .noSentencesLoaded:
            return "No sentences found when switching on inputFileTYpe"
        case .outputFolderCreationError:
            return "Can't create the output folder in sandbox"
        case .packageLoadFailed(let name):
            return "Failed to load model from package \(name)"
        case .parserCreationError(let file):
            return "Couldn't create XML parser from \(file.lastPathComponent)"
        case .predictionFailed(let error):
            return "The model failed to run: \(error.localizedDescription)"
        case .predictionFailedAtLogits(let message):
            return message
        case .resourceMissing(let name):
            return "Missing resource: \(name)"
        case .retokenisationError:
            return "Error retokenising: no sentences found"
        case .readFromSandboxError:
            return "Error reading the file from the sandbox"
        case .tokenizationFail(let message):
            return "Tokenisation failed :: \(message)"
        case .unexpectedOutput(let detail):
            return "Unexpected model output: \(detail)"
        case .utf8DecodeError:
            return "Failed to decode as UTF-8"
        case .xmlParserFailure:
            return "Unknown XML parsing error with XML parser + delegate"
        }
    }
}


enum PipelineStep: Int, CaseIterable, Identifiable, Comparable, Codable {
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

enum RegexStash{
    
    enum blobToSents{
        static let regex1 = try! Regex("\n\n")
        static let regex2 = try! Regex("\n")
        static let regex3 = try! Regex(#"\. ([A-Z])"#)
        static let overzealousPattern = try! Regex("U.S._EOS_")
    }
    
    enum tokeniseEN{
        static let enPunctuation = try! Regex(#"[\[\]()!?;:,\.\"]"#)
        static let apostopheCatcher = try! Regex(#"'s|s'"#)
        static let singleQuoteCatcher = try! Regex(#"[’''’]"#)
        static let doubleQuoteCatcher =  try! Regex(#"[“”]"#)
    }

    enum tokenisationGeneral{
        static let dashWithSpace = try! Regex(#" (-) "#)
        static let dashWithoutSpace = try! Regex(#"(–)"#)
        static let urlCatcher = try! Regex(#"(htt(p|ps)://.+?($| ))"#)
        static let ellipsisCatcher = try! Regex(#"..."#)
        static let multiSpaces = try! Regex(#"[^\S]+{2,}"#)
        static let multilinebreaks = try! Regex(#"[^\n]+{2,}"#)
        static let allTabs = try! Regex(#"[^\t]+{1,}"#)
        static let generalPunctuation = try! Regex(#"([,\]\[;:\-&\(\)?!\.«»“”"])"#)
        static let badSentenceEndings = try! Regex(#",\. |,\.$|\.,"#)
    }
    
    enum tokeniseFR{
        static let punctRegexFR = try! Regex(#"[\[\]()!?;:,\.\"]"#)
        static let contractionRegexFR = try! Regex(#"([cdjlmnrst]|qu)'"#)
        static let pronounRegexFR = try! Regex(#"(-je|-tu|-il|-elle|-on|-ça|-cela|-nous|-vous|-ils|-elles|-moi|-toi|-lui|-leur|-en|-y|-ilz)"#)
        static let eosBreakCatchRegexFR = try! Regex(#"[^\S\n]+{2,}"#)
    }
}

enum RetokenisationType: String, Identifiable, CaseIterable, Codable{
    var id: Self {self}
    case predict = "Predict"
    case manual = "Manual"
    case rule = "Rule"
    case skip = "skip" // special case for txt parsed from raw file - is already Hashable, so skip by toggling value
    }

enum SentencizingMethod: String, Identifiable, CaseIterable, Codable {
    var id: Self {self}
    case nlSentencizer
    case custom
    case naive
    case eosMark
    }

enum TokenizingMethod : String, Identifiable, CaseIterable, Codable{
    var id: Self {self}
    case custom = "Custom"
    case nltokeniser = "NLTokenizer"
    case trained = "Trained"
    case manual = "Manual"
    case skip = "Skip"
}

