//
//  CustomPickers.swift
//  Tagger
//
//  Created by Adam on 16/10/2026.
//

import SwiftUI
// combination of extension: Language and a protocol
// 1. Define a protocol that guarantees availableTBs exists
protocol TreebankProvidable {
    associatedtype TreebankType: Hashable
    var availableTBs: [TreebankType] { get }
    var defaultTB: TreebankType { get } //
}

// 2. Conforming  language enum to it
extension Language: TreebankProvidable {
    typealias TreebankType = Language.Treebank
}
///Similar pickers :: diff names, Binding, onChange logic
struct ConstrainedLanguagePickerView<T: Hashable & CaseIterable & RawRepresentable & TreebankProvidable>: View
where T.RawValue == String, T.TreebankType == Language.Treebank {
    let title: String
    @Binding var selectedTreebankDefault: Language.Treebank
    @Binding var selection: T

    var body: some View{
        Picker(title, selection: $selection){
            ForEach(Language.allCases){lang in
                Text(lang.displayName.uppercased())
            }
        }
        .onChange(of: selection) {
            if let first = $selection.wrappedValue.availableTBs.first {
                selectedTreebankDefault = first
            }
        }
    }
}
struct ConstrainedTreebankPickerView<T: Hashable & CaseIterable & RawRepresentable & TreebankProvidable>: View
where T.RawValue == String, T.TreebankType == Language.Treebank {
    let title: String
    @Binding var selectedLang: T // here, selection is lang
    @Binding var selectedTreebank: Language.Treebank

    var body: some View{
        Picker(title, selection: $selectedTreebank){
            ForEach(selectedLang.availableTBs, id:\.self){tb in
                Text(tb.short).tag(tb)
            }
        }
        .onChange(of: selectedLang){
            selectedTreebank = selectedLang.defaultTB
        }
    }
}

struct DefaultPickerView<T: Hashable & CaseIterable & RawRepresentable>: View where T.RawValue == String {
    // 1. The parameters you want to pass in
    let title: String
    @Binding var selection: T
    var accessibilityLabelString: String? = nil
    var onChangeAction: ((T) -> Void)? = nil

    var body: some View {
        Picker(title, selection: $selection) {
            // 2. Iterate over all cases of whatever enum is passed in
            ForEach(Array(T.allCases), id: \.self) { option in
                Text(option.rawValue)
                    .tag(option) // 3. Automatically sets the tag
            }
        }
    }
}
