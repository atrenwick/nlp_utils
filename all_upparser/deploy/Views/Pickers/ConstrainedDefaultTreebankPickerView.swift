//
//  ConstrainedTreebankPickerView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//

import SwiftUI

struct ConstrainedDefaultTreebankPickerView<T: Hashable & CaseIterable & RawRepresentable & TreebankProvidable>: View
where T.RawValue == String, T.TreebankType == Language.Treebank {
    let title: String
    @Binding var selectedLang: T // here, selection is lang
    @Binding var selectedTreebank: Language.Treebank
    @Binding var selectedArchitecture: ModelArchitecture

    var body: some View{
        Picker(title, selection: $selectedTreebank){
            ForEach(availableTreebanks, id:\.self){tb in
                Text(tb.short).tag(tb)
            }
        }
        .onChange(of: selectedLang){
            selectedTreebank = selectedLang.defaultTB
        }
    }
}


extension ConstrainedDefaultTreebankPickerView{
    var availableTreebanks: [Language.Treebank] {
        ConfigurationRules.availableTreebanks(for: selectedArchitecture, language: selectedLang as! Language)
            .sorted {$0.shortTidy < $1.shortTidy}
    }
}

