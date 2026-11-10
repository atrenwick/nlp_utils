//
//  CustomPickers.swift
//  Tagger
//
//  Created by Adam on 16/10/2026.
//

import SwiftUI

/// Customised Architecture picker for model architectures, with onChange modifiers
struct ArchitecturePickerView: View{
    @Binding var myConfig: TaggerConfig
    
    var body: some View {
        Picker("Architecture", selection: $myConfig.parsingConfig.modelArchitecture){
            ForEach(ModelArchitecture.allCases.sorted {$0.rawValue < $1.rawValue }){modarch in
                Text(modarch.displayName)
            }
        }.onChange(of: myConfig.parsingConfig.modelArchitecture){
            if myConfig.parsingConfig.modelArchitecture == .distilbert && myConfig.inputConfig.inputFileType == .txt {myConfig.parsingConfig.tokenizingMethod = .nltokeniser}
        }
    }
}

/// Customised picker for languages with constraints on language and onChange modifiers
struct ConstrainedPickerForLang: View{
    @Binding var myConfig: TaggerConfig

    var availableLanguages: [Language] {
        ConfigurationRules.availableLanguages(for: myConfig.parsingConfig.modelArchitecture)
            .sorted {$0.rawValue < $1.rawValue}
    }
    var body: some View{
        Picker("Language", selection: $myConfig.parsingConfig.selectedLanguage){
            ForEach(availableLanguages){lang in
                Text(lang.displayName.uppercased())
            }
        }
        .onChange(of: myConfig.parsingConfig.modelArchitecture) {
            if !myConfig.parsingConfig.selectedLanguage.availableArchs.contains(myConfig.parsingConfig.modelArchitecture) || !myConfig.parsingConfig.selectedLanguage.availableTBs.contains(myConfig.parsingConfig.selectedTreebank){
                if let first = availableLanguages.first {
                    myConfig.parsingConfig.selectedLanguage = first
                    if let firstTB = myConfig.parsingConfig.selectedLanguage.availableTBs.first {
                        myConfig.parsingConfig.selectedTreebank = firstTB
                    }
                }
            }
        }
        .onChange(of: myConfig.parsingConfig.selectedLanguage) {
            if let first = myConfig.parsingConfig.selectedLanguage.availableTBs.first {
                myConfig.parsingConfig.selectedTreebank = first
            }
        }
        .onChange(of: myConfig.inputConfig.selectedInputFile){
            if myConfig.inputConfig.detectLanguage {
                if let detectedLang = FileIngestionWorkflow.detectLangInFilename(inputURL:myConfig.inputConfig.selectedInputFile){
                    myConfig.parsingConfig.selectedLanguage = detectedLang
                }
            }
        }
    }
}
/// Customised picker for treebanks based on selected language, with fallbacks, default
struct ConstrainedPickerForTB: View{
    @Binding var myConfig: TaggerConfig
    
    var availableTreebanks: [Language.Treebank] {
        ConfigurationRules.availableTreebanks(
            for: myConfig.parsingConfig.modelArchitecture,
            language: myConfig.parsingConfig.selectedLanguage
        )
    }
    
    var body: some View{
        Picker("Treebank", selection: $myConfig.parsingConfig.selectedTreebank){
            ForEach(availableTreebanks.sorted {$0.rawValue < $1.rawValue}, id:\.self){tb in
                Text(tb.shortTidy).tag(tb)
            }
        }
        .onChange(of: myConfig.parsingConfig.selectedLanguage) {
            if !myConfig.parsingConfig.selectedLanguage.availableTBs.contains(myConfig.parsingConfig.selectedTreebank){
                if let first = myConfig.parsingConfig.selectedLanguage.availableTBs.first {
                    myConfig.parsingConfig.selectedTreebank = first
                }
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
    @Binding var myConfig: TaggerConfig
    @Binding var  fileContainerModel: SourceFileContainerModel
    var body: some View {
        Toggle(isOn: $myConfig.inputConfig.detectLanguage) {
            Text("Autodetect Language")
        }.onChange(of: myConfig.inputConfig.detectLanguage){_, newValue in
            if newValue == true, let detectedLang =  FileIngestionWorkflow.detectLangInFilename(inputURL:fileContainerModel.localSandboxFileURL){
                myConfig.parsingConfig.selectedLanguage = detectedLang
            } else {print("case 3")}
        }
        .accessibilityIdentifier("DetectLanguageToggle")
        
        Toggle(isOn: $myConfig.inputConfig.matchFileNameType) {
            Text("Automatch filename-type")
        }.onChange(of: myConfig.inputConfig.matchFileNameType){_, newValue in
            if newValue == true, let detectedValue = fileContainerModel.localSandboxFileURL?.pathExtension {
                if let convertedExt = InputFileType(rawValue: detectedValue.replacingOccurrences(of: ".", with: "")){
                    myConfig.inputConfig.inputFileType = convertedExt
                }
            }
        }
    }
}

