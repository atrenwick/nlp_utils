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
        case.ANG: return [.angTB1]
        }
    }
}


enum TokenisationMethod: String, CaseIterable, Identifiable {
    var id: Self {self}
    case conll
//    case naive
    case retokenise
}



