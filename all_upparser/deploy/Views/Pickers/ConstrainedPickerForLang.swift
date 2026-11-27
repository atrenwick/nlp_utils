//
//  ConstrainedPickerForLang.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI

/// Customised picker for languages with constraints on language and onChange modifiers
struct ConstrainedPickerForLangView: View{
    @Environment(AppModel.self) private var model
    
    var body: some View{
        @Bindable var model = model
        Picker("Language", selection: $model.myConfig.parsingConfig.selectedLanguage){
            ForEach(availableLanguages){lang in
                Text(lang.displayName.uppercased())
            }
        }
        .onChange(of: model.myConfig.parsingConfig.modelArchitecture) {
            updateLangAndTB()
        }
        .onChange(of: model.myConfig.parsingConfig.selectedLanguage) {
            updateSelectedModel()
        }
        .onChange(of: model.myConfig.inputConfig.selectedInputFile){
            updateSelectedLanguage()
            
        }
    }
}

extension ConstrainedPickerForLangView{
    var availableLanguages: [Language] {
        ConfigurationRules.availableLanguages(for: model.myConfig.parsingConfig.modelArchitecture)
            .sorted {$0.rawValue < $1.rawValue}
    }
    var archCondition: Bool {
        !model.myConfig.parsingConfig.selectedLanguage.availableArchs.contains(model.myConfig.parsingConfig.modelArchitecture)
    }
    var tbCondition: Bool {
        !model.myConfig.parsingConfig.selectedLanguage.availableTBs.contains(model.myConfig.parsingConfig.selectedTreebank)
    }
    
    func updateLangAndTB(){
        if archCondition || tbCondition {
            if let first = availableLanguages.first {
                model.myConfig.parsingConfig.selectedLanguage = first
                if let firstTB = model.myConfig.parsingConfig.selectedLanguage.availableTBs.first {
                    model.myConfig.parsingConfig.selectedTreebank = firstTB
                }
            }
        }
    }
    
    func updateSelectedModel(){
        if let first = model.myConfig.parsingConfig.selectedLanguage.availableTBs.first {
            model.myConfig.parsingConfig.selectedTreebank = first
        }
    }
    
    func updateSelectedLanguage(){
        if model.myConfig.inputConfig.detectLanguage {
            if let detectedLang = FileIngestionWorkflow.detectLangInFilename(inputURL:model.myConfig.inputConfig.selectedInputFile){
                model.myConfig.parsingConfig.selectedLanguage = detectedLang
            }
        }
    }
    
}
