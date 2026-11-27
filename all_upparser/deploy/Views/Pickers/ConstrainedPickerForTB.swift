//
//  ConstrainedPickerForTB.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI


/// Customised picker for treebanks based on selected language, with fallbacks, default
struct ConstrainedPickerForTBView: View{
    @Environment(AppModel.self) private var model

    var body: some View{
        @Bindable var model = model

        Picker("Treebank", selection: $model.myConfig.parsingConfig.selectedTreebank){
            ForEach(availableTreebanks.sorted {$0.rawValue < $1.rawValue}, id:\.self){tb in
                Text(tb.shortTidy).tag(tb)
            }
        }
        .onChange(of: model.myConfig.parsingConfig.selectedLanguage) {
        }
    }
}

extension ConstrainedPickerForTBView{
    
    var availableTreebanks: [Language.Treebank] {
        ConfigurationRules.availableTreebanks(
            for: model.myConfig.parsingConfig.modelArchitecture,
            language: model.myConfig.parsingConfig.selectedLanguage
        )
    }
    
    var isSelectedTBavailable: Bool {
        !model.myConfig.parsingConfig.selectedLanguage.availableTBs.contains(model.myConfig.parsingConfig.selectedTreebank)
    }
    
    func updateSelectedTB() {
        if isSelectedTBavailable, let first = model.myConfig.parsingConfig.selectedLanguage.availableTBs.first {
            model.myConfig.parsingConfig.selectedTreebank = first
        }
    }
    
    
}
