//
//  XMLSettingView.swift
//  Tagger
//
//  Created by Adam on 11/09/2026.
//

import SwiftUI


struct ExportSettingsDetailView: View{
    @Binding var selectedExportFormat: ExportFormat
    @Binding var xmlAuthorName: String
    @Binding var xmlTitle: String
    @Binding var includeConllSentIdLine: Bool
    @Binding var includeConllSentText: Bool
    @FocusState var isFocused
    
    var body: some View{
        Form{
            if [.xmlConll, .conll, .conllTxt, .conllTidy].contains(selectedExportFormat){
                Section("CoNLL Settings"){
                    Toggle(isOn: $includeConllSentIdLine) {
                        Text("Add Conll Meta sent_ID")
                    }
                    Toggle(isOn: $includeConllSentText) {
                        Text("Add conll meta sent_text")
                    }
                }
            }
                //XML settings
                if [.xmlConll, .xml].contains(selectedExportFormat){
                    Section("XML Settings"){
                        TextField("XML Author", text: $xmlAuthorName)
                            .textInputAutocapitalization(TextInputAutocapitalization.never)
                            .autocorrectionDisabled()
                            .onChange(of: xmlAuthorName) { _, newValue in
                                let cleaned = xmlAuthorName.xmlEscaped
                                if cleaned != newValue {
                                    xmlAuthorName = cleaned
                                }
                            }
                            .focused($isFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                isFocused = false
                            }
                        TextField("XML Title", text: $xmlTitle)
                            .textInputAutocapitalization(TextInputAutocapitalization.never)
                            .autocorrectionDisabled()
                            .onChange(of: xmlTitle) { _, newValue in
                                let cleaned = xmlTitle.xmlEscaped
                                if cleaned != newValue {
                                    xmlTitle = cleaned
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
    @Previewable @State var selectedExportFormat: ExportFormat = .xmlConll
    @Previewable @State var xmlAuthorName: String = "CustomXML authorname"
    @Previewable @State var xmlTitle: String = "Custom XML title"
    @Previewable @State var includeConllSentIdLine: Bool = true
    @Previewable @State var includeConllSentText: Bool = false

    ExportSettingsDetailView(
        selectedExportFormat: $selectedExportFormat,
        xmlAuthorName: $xmlAuthorName,
        xmlTitle: $xmlTitle,
        includeConllSentIdLine: $includeConllSentIdLine,
        includeConllSentText: $includeConllSentText

    )
}


