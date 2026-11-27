//
//  MatchDetectToggleView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI


/// Toggle for Automatically match, detect filename-type
struct MatchDetectToggleView: View{
     @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Toggle(isOn: $model.myConfig.inputConfig.detectLanguage) {
            Text("Autodetect Language")
        }.onChange(of: model.myConfig.inputConfig.detectLanguage, updateSelectedLang)
        .accessibilityIdentifier("DetectLanguageToggle")
        
        Toggle(isOn: $model.myConfig.inputConfig.matchFileNameType) {
            Text("Automatch filename-type")
        }.onChange(of: model.myConfig.inputConfig.matchFileNameType, updateInputFileType)
        
    }
}

extension MatchDetectToggleView{
    
    func updateSelectedLang(oldValue: Bool, newValue: Bool) {
        guard newValue,
              let detectedLang = FileIngestionWorkflow.detectLangInFilename(inputURL:model.fileContainerModel.localSandboxFileURL)
        else { return }
     
        model.myConfig.parsingConfig.selectedLanguage = detectedLang
    }
    
    func updateInputFileType(_ oldValue: Bool, _ newValue: Bool) {
        guard newValue,
              let detectedValue = model.fileContainerModel.localSandboxFileURL?.pathExtension,
              let convertedExt = InputFileType(rawValue: detectedValue.replacingOccurrences(of: ".", with: ""))
        else { return }

        model.myConfig.inputConfig.inputFileType = convertedExt
    }
}
