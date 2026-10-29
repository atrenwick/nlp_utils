//
//  XMLSettingView.swift
//  Tagger
//
//  Created by Adam on 11/09/2026.
//

import SwiftUI


struct ExportSettingsDetailView: View{
    @Binding var myConfig: TaggerConfig
    @FocusState var isFocused
    
    var body: some View{
        Form{
            if [.xmlConll, .conll, .conllTxt, .conllTidy].contains(myConfig.exportConfig.selectedExportFormat){
                Section("CoNLL Settings"){
                    Toggle(isOn: $myConfig.exportConfig.includeConllSentIdLine) {
                        Text("Add Conll Meta sent_ID")
                    }
                    Toggle(isOn: $myConfig.exportConfig.includeConllSentText) {
                        Text("Add conll meta sent_text")
                    }
                }
            }
                //XML settings
            if [.xmlConll, .xml].contains(myConfig.exportConfig.selectedExportFormat){
                    Section("XML Settings"){
                        TextField("XML Author", text: $myConfig.exportConfig.xmlAuthorName)
                            .textInputAutocapitalization(TextInputAutocapitalization.never)
                            .autocorrectionDisabled()
                            .onChange(of: myConfig.exportConfig.xmlAuthorName) { _, newValue in
                                let cleaned = myConfig.exportConfig.xmlAuthorName.xmlEscaped
                                if cleaned != newValue {
                                    myConfig.exportConfig.xmlAuthorName = cleaned
                                }
                            }
                            .focused($isFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                isFocused = false
                            }
                        TextField("XML Title", text: $myConfig.exportConfig.xmlTitle)
                            .textInputAutocapitalization(TextInputAutocapitalization.never)
                            .autocorrectionDisabled()
                            .onChange(of: myConfig.exportConfig.xmlTitle) { _, newValue in
                                let cleaned = myConfig.exportConfig.xmlTitle.xmlEscaped
                                if cleaned != newValue {
                                    myConfig.exportConfig.xmlTitle = cleaned
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
    @Previewable @State var myConfig: TaggerConfig = TaggerConfig()
    ExportSettingsDetailView(myConfig: $myConfig)
}


