//
//  Structures.swift
//  Tagger
//
//  Created by Adam on 10/09/2026.
//

import Foundation


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
    
}


enum Language: String, CaseIterable, Identifiable {
    // uppercase lang code as used in file paths
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
    
    var defaultTB: Treebank {
        switch self {
        case .EN: return .enTB1
        case .ANG: return .angTB1
        case .FR: return .frTB1
        case .DE: return .deTB1
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

//    var displayName: String{
//        switch self{
//        case .predict: return "Predict"
//        case .manual: return "Manual"
//        case .rule: return "Rule"
//    }
}

//enum TokenisationMethod: String, CaseIterable, Identifiable {
//    var id: Self {self}
//    case conll
////    case naive
//    case retokenise
//    case xml
//}
//
