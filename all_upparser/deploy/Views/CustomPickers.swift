//
//  CustomPickers.swift
//  Tagger
//
//  Created by Adam on 16/10/2026.
//

import SwiftUI

/// Customised Architecture picker for model architectures, with onChange modifiers
struct ArchitecturePickerView: View{
     @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("Architecture", selection: $model.myConfig.parsingConfig.modelArchitecture){
            ForEach(ModelArchitecture.allCases.sorted {$0.rawValue < $1.rawValue }){modarch in
                Text(modarch.displayName)
            }
        }.onChange(of: model.myConfig.parsingConfig.modelArchitecture){
            if model.myConfig.parsingConfig.modelArchitecture == .distilbert && model.myConfig.inputConfig.inputFileType == .txt {model.myConfig.parsingConfig.tokenizingMethod = .nltokeniser}
        }
    }
}

/// Customised picker for languages with constraints on language and onChange modifiers
struct ConstrainedPickerForLang: View{
    @Environment(AppModel.self) private var model
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
    
    var body: some View{
        @Bindable var model = model
        Picker("Language", selection: $model.myConfig.parsingConfig.selectedLanguage){
            ForEach(availableLanguages){lang in
                Text(lang.displayName.uppercased())
            }
        }
        .onChange(of: model.myConfig.parsingConfig.modelArchitecture) {
            if archCondition || tbCondition{
                if let first = availableLanguages.first {
                    model.myConfig.parsingConfig.selectedLanguage = first
                    if let firstTB = model.myConfig.parsingConfig.selectedLanguage.availableTBs.first {
                        model.myConfig.parsingConfig.selectedTreebank = firstTB
                    }
                }
            }
        }
        .onChange(of: model.myConfig.parsingConfig.selectedLanguage) {
            if let first = model.myConfig.parsingConfig.selectedLanguage.availableTBs.first {
                model.myConfig.parsingConfig.selectedTreebank = first
            }
        }
        .onChange(of: model.myConfig.inputConfig.selectedInputFile){
            if model.myConfig.inputConfig.detectLanguage {
                if let detectedLang = FileIngestionWorkflow.detectLangInFilename(inputURL:model.myConfig.inputConfig.selectedInputFile){
                    model.myConfig.parsingConfig.selectedLanguage = detectedLang
                }
            }
        }
    }
}
/// Customised picker for treebanks based on selected language, with fallbacks, default
struct ConstrainedPickerForTB: View{
    @Environment(AppModel.self) private var model

    var availableTreebanks: [Language.Treebank] {
        ConfigurationRules.availableTreebanks(
            for: model.myConfig.parsingConfig.modelArchitecture,
            language: model.myConfig.parsingConfig.selectedLanguage
        )
    }
    var tbCondition: Bool {
        !model.myConfig.parsingConfig.selectedLanguage.availableTBs.contains(model.myConfig.parsingConfig.selectedTreebank)
    }
    var body: some View{
        @Bindable var model = model

        Picker("Treebank", selection: $model.myConfig.parsingConfig.selectedTreebank){
            ForEach(availableTreebanks.sorted {$0.rawValue < $1.rawValue}, id:\.self){tb in
                Text(tb.shortTidy).tag(tb)
            }
        }
        .onChange(of: model.myConfig.parsingConfig.selectedLanguage) {
            if tbCondition, let first = model.myConfig.parsingConfig.selectedLanguage.availableTBs.first {
                    model.myConfig.parsingConfig.selectedTreebank = first
            }
        }
    }
}

/////Similar pickers :: diff names, Binding, onChange logic
// this gets used in SetDefaults, where myConfig doesn't exist
struct ConstrainedLanguagePickerView<T: Hashable & CaseIterable & RawRepresentable & TreebankProvidable>: View
where T.RawValue == String, T.TreebankType == Language.Treebank {
    let title: String
    @Binding var selectedTreebankDefault: Language.Treebank
    @Binding var selection: T
    @Binding var selectedArchitecture: ModelArchitecture

    var availableLanguages: [Language] {
        ConfigurationRules.availableLanguages(for: selectedArchitecture)
        }

    var body: some View{
        Picker(title, selection: $selection){
            ForEach(availableLanguages.sorted {$0.rawValue < $1.rawValue} ){lang in
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
    @Binding var selectedArchitecture: ModelArchitecture
    var availableTreebanks: [Language.Treebank] {
        ConfigurationRules.availableTreebanks(for: selectedArchitecture, language: selectedLang as! Language)
        }

    var body: some View{
        Picker(title, selection: $selectedTreebank){
            ForEach(availableTreebanks.sorted {$0.rawValue < $1.rawValue}, id:\.self){tb in
                Text(tb.short).tag(tb)
            }
        }
        .onChange(of: selectedLang){
            selectedTreebank = selectedLang.defaultTB
        }
    }
}

struct DefaultPickerView<T: Hashable & CaseIterable & RawRepresentable>: View where T.RawValue == String {
    let title: String
    @Binding var selection: T
    var accessibilityLabelString: String? = nil
    var onChangeAction: ((T) -> Void)? = nil

    // optional to yield tokenising method if T is Tokenizing method
    var itemToDrop: T? {
        if title.contains("txt tokMethod failover") {
            // Safely attempt to cast .whale to whatever generic type T currently is
            return TokenizingMethod.trained as? T
        }
        return nil
    }

    // 2. Filter the cases using a nil check
    var filteredCases: [T] {
        if let dropItem = itemToDrop {
            // If we have an item to drop, filter it out!
            return T.allCases.filter { $0 != dropItem }
        } else {
            // Otherwise, return all cases normally (or if T is a different enum type)
            return Array(T.allCases)
        }
    }
    
    var body: some View {
        Picker(title, selection: $selection) {
            // 2. Iterate over all cases of whatever enum is passed in
            ForEach(filteredCases.sorted {$0.rawValue < $1.rawValue}, id: \.self) { option in
                Text (["after","before"].contains(option.rawValue) ? option.rawValue.localizedCapitalized : option.rawValue)
                //                Text(option.rawValue)
                    .tag(option) // 3. Automatically sets the tag
            }
        }
    }
}

/// Toggle for Automatically match, detect filename-type
struct MatchDetectToggleView: View{
     @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Toggle(isOn: $model.myConfig.inputConfig.detectLanguage) {
            Text("Autodetect Language")
        }.onChange(of: model.myConfig.inputConfig.detectLanguage){_, newValue in
            if newValue == true, let detectedLang =  FileIngestionWorkflow.detectLangInFilename(inputURL:model.fileContainerModel.localSandboxFileURL){
                model.myConfig.parsingConfig.selectedLanguage = detectedLang
            } else {print("case 3")}
        }
        .accessibilityIdentifier("DetectLanguageToggle")
        
        Toggle(isOn: $model.myConfig.inputConfig.matchFileNameType) {
            Text("Automatch filename-type")
        }.onChange(of: model.myConfig.inputConfig.matchFileNameType){_, newValue in
            if newValue == true, let detectedValue = model.fileContainerModel.localSandboxFileURL?.pathExtension {
                if let convertedExt = InputFileType(rawValue: detectedValue.replacingOccurrences(of: ".", with: "")){
                    model.myConfig.inputConfig.inputFileType = convertedExt
                }
            }
        }
    }
}

