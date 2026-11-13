//
//  enumerations
//  Tagger
//
//  Created by Adam on 10/09/2026.
//

import Foundation
internal import UniformTypeIdentifiers

/// ultrasimple enumeration used for getting URLs for tagging assets
enum AssetType: String{
    case mlmodelc
    case json
}

/// architecture for ML model used for annotation
enum ModelArchitecture: String, CaseIterable, Identifiable{
    var id: Self { self }
    case distilbert
    case cnnBiLSTM
    case camembert
    case rnn
    case roberta
    var displayName: String{
        switch self{
        case .distilbert: return "DistilBERT"
        case .cnnBiLSTM: return "CNN-BiLSTM"
        case .camembert: return "CamemBERT"
        case .rnn: return "RNN"
        case .roberta: return "XLM-roBERTa"
        }
    }
    
    var keyChunk: String{
        switch self{
        case .distilbert: return "DIS"
        case .cnnBiLSTM: return "CNN"
        case .camembert: return "CAM"
        case .rnn: return "RNN"
        case .roberta: return "ROB"
        }
    }
}

enum ConllLineContent {
    case row(Token)
    case blank
}

/// direction in which to process tokens looking at either the current token or the next token
enum EosApproach{
    case current
    case next
}

/// export format for annotations
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

/// file type for files to be tagged
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
    
    /// var linking specific file extensions to plainText type
    var utType: UTType{
        switch self {
        case .conll, .manual, .txt: return .plainText
        case .xml, .xmlConll: return UTType(filenameExtension: "xml") ?? .plainText
        }
    }
}

/// position where new items should be placed relative to the row selected
/// used in forms allowing manual addition of items
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
    case ENM
    
    var id: Self { self }
    var displayName: String {
        switch self {
        case .EN: return "en"
        case .FR: return "fr"
        case .DE: return "de"
        case .ANG: return "ang"
        case .FRM: return "frm"
        case .FRO: return "fro"
        case .ENM: return "enm"
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
        case .ENM: return .enmTB1
        }
    }

    var keyChunk: String {
        switch self {
        case .EN: return "ENG"
        case .ANG: return "ANG"
        case .FR: return "FRA"
        case .DE: return "DEU"
        case .FRO: return "FRO"
        case .FRM: return "FRO"
        case .ENM: return "ENM"
        }
    }

    var keyChunkFlag: String {
        switch self {
        case .EN: return "🇬🇧 ENG"
        case .ANG: return "ANG"
        case .FR: return "🇫🇷 FRA"
        case .DE: return "🇩🇪 DEU"
        case .FRO: return "FRO"
        case .FRM: return "FRM"
        case .ENM: return "🏴󠁧󠁢󠁥󠁮󠁧󠁿 ENM"
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
        case enmTB1 = "rnn"
        
        var id: String { rawValue }
        
        var shortTidy: String {
            // RHS of model files and Picker strings
            switch self {
            case .enTB1: return "EWT"
            case .enTB2: return "GUM"
            case .enTB3: return "LINES"
            case .frTB1, .deTB1: return "GSD"
            case .frTB2: return "Sequoia"
            case .frTB3: return "Rhapsodie"
            case .deTB2: return "HDT"
            case .angTB1: return "OEDT"
            case .frmTB1, .froTB1: return "Profiterole"
            case .enmTB1: return "RNN"
            }
        }
        var keyChunk: String {
            // RHS of model files and Picker strings
            switch self {
            case .enTB1: return "EWT"
            case .enTB2: return "GUM"
            case .enTB3: return "LIN"
            case .deTB1, .frTB1: return "GSD"
            case .frTB2: return "SEQ"
            case .frTB3: return "RHA"
            case .deTB2: return "HDT"
            case .angTB1: return "OED"
            case .froTB1, .frmTB1: return "PRO"
            case .enmTB1: return "RNN"
            }
        }
        var short: String {
            // RHS of model files and Picker strings
            switch self {
            case .enTB1: return "ewt"
            case .enTB2: return "gum"
            case .enTB3: return "lines"
            case .deTB1, .frTB1: return "gsd"
            case .frTB2: return "sequoia"
            case .frTB3: return "rhapsodie"
            case .deTB2: return "hdt"
            case .angTB1: return "oedt"
            case .froTB1, .frmTB1: return "profiterole"
            case .enmTB1: return "RNN"
            }
        }
    }
    var availableArchs: [ModelArchitecture]{
        switch self {
        case .FR: return [.cnnBiLSTM, .distilbert, .camembert, .roberta, .rnn]
        case .EN: return [.cnnBiLSTM,.rnn, .roberta]
        case .ENM: return [.rnn]
        case .ANG: return [.distilbert, .cnnBiLSTM]
        case .FRM: return [.distilbert, .rnn, .cnnBiLSTM]
        case .FRO: return [.distilbert, .rnn, .cnnBiLSTM]
        case .DE : return [.cnnBiLSTM, .distilbert]
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
        case .ENM: return [.enmTB1]
        }
    }
}

/// source for lemmas : via rule-based or hybrid method
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

/// possible results of post-processing a sentence
enum OnSentResultType: String, RawRepresentable, CaseIterable{
    var id : Self {self}
    case empty
    case tooManyWords
    case tooManySubtoks
    case success
    case otherError
}

/// parsing a document with a single parser, or with multiple, successive but independent parsers
enum ParsingType: String, Identifiable, CaseIterable {
    var id: Self {self}
    case single
    case multi
}

/// Which pipeline steps should be run
enum PipelineStep: Int, CaseIterable, Identifiable, Comparable, Codable {
    /// RawValue type (Int) links each case to an integer (1, 2, 3, 4).
    /// Comparable conformance allows using <, >, <=, >= on enum cases.
    /// step1 is tokenisation, and is handled with diff pipe
    case step2 = 2
    case step3 = 3
    case step4 = 4
    case step5 = 5
    
    /// raw value = id, to conform to Identifiable
    var id: Int { rawValue }
    
    /// Computed property: evaluates 'self' on demand and returns the matching  string
    var title: String {
        switch self {
        case .step2: return "2. POS tag"
        case .step3: return "3. Lemmas"
        case .step4: return "4. Feats"
        case .step5: return "5. DepParse"
        }
    }
    /// required for Comparable : Swift expects this to build other comparison operattions
    static func < (lhs: PipelineStep, rhs: PipelineStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// general stash of regexes for tokenisation and sentencisation
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

/// status of processing by an annotation pipeline
enum ProcessingStatus: String, CaseIterable, Codable {
    case notstarted
    case inprogress
    case interrupted
    case success
    case failed
    
    var exitStatus: String {
        switch self {
        case .notstarted: return "Not Started"
        case .inprogress:  return "In Progress"
        case .interrupted: return "Interrupted"
        case .success: return "Success"
        case .failed: return "Failed"
        }
    }

    var interruptRequested: String {
        switch self {
            case .interrupted:
                return "True"
            default:
                return "False"
        }
    }
}

/// reset the export directory to which location
enum ResetDirOption{
    case defaultvalue
    case sandbox
}

/// strategies to apply when retokenising already tokenised text
/// skip is special case for txt parsed from raw file - is already Hashable, so skip by toggling value
enum RetokenisationType: String, Identifiable, CaseIterable, Codable{
    var id: Self {self}
    case predict = "Predict"
    case manual = "Manual"
    case rule = "Rule"
    case skip = "skip"
    }

/// strategies for dividing texts into sentences
enum SentencizingMethod: String, Identifiable, CaseIterable, Codable {
    var id: Self {self}
    case nlSentencizer
    case custom
    case naive
    case eosMark
    
    var tidyName: String {
        switch self {
        case .nlSentencizer: return "NLSentencizer"
        case .custom: return "Custom"
        case .naive: return "Naive"
        case .eosMark: return "EOS Mark"
        }
    }
}

/// keys used in reading, writing defaults for output directory, as URL and Data
enum StoreKey {
    static let outputDir = "outputDirDefault"        // URL (for comparison/display)
    static let outputBookmark = "outputDirBookmark"  // Data (for access)
}

/// strategies for tokenising text
enum TokenizingMethod : String, Identifiable, CaseIterable, Codable{
    var id: Self {self}
    case custom = "Custom"
    case nltokeniser = "NLTokenizer"
    case trained = "Trained"
    case manual = "Manual"
    case skip = "Skip"
}
