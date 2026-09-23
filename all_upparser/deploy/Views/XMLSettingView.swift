//
//  XMLSettingView.swift
//  Tagger
//
//  Created by Adam on 11/09/2026.
//

import SwiftUI

struct XMLSettingView: View {
    @Binding var selectedExportFormat: ExportFormat
    @Binding var xmlAuthorName: String
    @Binding var xmlTitle: String
    @FocusState var isFocused
    var body: some View {
        switch selectedExportFormat {
        case .conll, .conllTidy, .conllTxt:
            Text("XML settings not relevant")
            
        case .xml, .xmlConll:
            Form{
                TextField("XML Author", text: $xmlAuthorName)
                    .textInputAutocapitalization(TextInputAutocapitalization.never)
                    .autocorrectionDisabled()
                    .onChange(of: xmlAuthorName) { _, newValue in
                        // Strip any forbidden characters immediately as typed or pasted
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
                        // Strip any forbidden characters immediately as typed or pasted
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

#Preview {
    @Previewable @State var selectedExportFormat: ExportFormat = .xml
    @Previewable @State var xmlAuthorName: String = ""
    @Previewable @State var xmlTitle: String = ""
    XMLSettingView(
        selectedExportFormat: $selectedExportFormat,
        xmlAuthorName: $xmlAuthorName,
        xmlTitle: $xmlTitle
    )
}


