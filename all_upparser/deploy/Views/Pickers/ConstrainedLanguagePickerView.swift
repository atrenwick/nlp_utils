//
//  ConstrainedLanguagePickerView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI

/////Similar pickers :: diff names, Binding, onChange logic
// this gets used in SetDefaults, where myConfig doesn't exist
struct ConstrainedLanguagePickerView<T: Hashable & CaseIterable & RawRepresentable & TreebankProvidable>: View
where T.RawValue == String, T.TreebankType == Language.Treebank {
    let title: String
    @Binding var selectedTreebankDefault: Language.Treebank
    @Binding var selection: T
    @Binding var selectedArchitecture: ModelArchitecture


    var body: some View{
        Picker(title, selection: $selection){
            ForEach(availableLanguages.sorted {$0.rawValue < $1.rawValue} ){lang in
                Text(lang.displayName.uppercased())
            }
        }
        .onChange(of: selection) { updateSelectedTB() }
    }
}


extension ConstrainedLanguagePickerView{
    var availableLanguages: [Language] {
        ConfigurationRules.availableLanguages(for: selectedArchitecture)
        }
    
    func updateSelectedTB(){
        if let first = $selection.wrappedValue.availableTBs.first {
            selectedTreebankDefault = first
        }

    }
}
