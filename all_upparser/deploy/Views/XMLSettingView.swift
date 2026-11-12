//
//  XMLSettingView.swift
//  Tagger
//
//  Created by Adam on 11/09/2026.
//
import SwiftUI

struct ExportSettingsDetailView: View{
    @Environment(AppModel.self) internal var model
    @FocusState var isFocused
    
    var body: some View{
        @Bindable var model = model
        Form{
            if [.xmlConll, .conll, .conllTxt, .conllTidy].contains(model.myConfig.exportConfig.selectedExportFormat){
                Section("CoNLL Settings"){
                    Toggle(isOn: $model.myConfig.exportConfig.includeConllSentIdLine) {
                        Text("Add Conll Meta sent_ID")
                    }
                    Toggle(isOn: $model.myConfig.exportConfig.includeConllSentText) {
                        Text("Add conll meta sent_text")
                    }
                }
            }
                //XML settings
            if [.xmlConll, .xml].contains(model.myConfig.exportConfig.selectedExportFormat){
                    Section("XML Settings"){
                        TextField("XML Author", text: $model.myConfig.exportConfig.xmlAuthorName)
                            .textInputAutocapitalization(TextInputAutocapitalization.never)
                            .autocorrectionDisabled()
                            .onChange(of: model.myConfig.exportConfig.xmlAuthorName) { _, newValue in
                                let cleaned = model.myConfig.exportConfig.xmlAuthorName.xmlEscaped
                                if cleaned != newValue {
                                    model.myConfig.exportConfig.xmlAuthorName = cleaned
                                }
                            }
                            .focused($isFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                isFocused = false
                            }
                        TextField("XML Title", text: $model.myConfig.exportConfig.xmlTitle)
                            .textInputAutocapitalization(TextInputAutocapitalization.never)
                            .autocorrectionDisabled()
                            .onChange(of: model.myConfig.exportConfig.xmlTitle) { _, newValue in
                                let cleaned = model.myConfig.exportConfig.xmlTitle.xmlEscaped
                                if cleaned != newValue {
                                    model.myConfig.exportConfig.xmlTitle = cleaned
                                }
                            }
                            .focused($isFocused)
                            .submitLabel(.go)
                            .onSubmit {
                                isFocused = false
                            }
                    }
                }
        }
    }
}
#Preview {
    ExportSettingsDetailView().environment(AppModel())
}
