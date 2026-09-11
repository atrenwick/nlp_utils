//
//  XMLSettingView.swift
//  Tagger
//
//  Created by Adam on 11/09/2026.
//

import SwiftUI

struct XMLSettingView: View {
    @Binding var selectedXMLoutputType: XMLOutputType
    @Binding var xmlAuthorName: String
    @Binding var xmlTitle: String
    var body: some View {
        Form{
            TextField("XML Author", text: $xmlAuthorName)
                .textInputAutocapitalization(TextInputAutocapitalization.never)
                .autocorrectionDisabled()
            TextField("Title", text: $xmlTitle)
                .textInputAutocapitalization(TextInputAutocapitalization.never)
                .autocorrectionDisabled()
            
            HStack {
                Text("Output type")
                Spacer()
                Picker("Output type", selection: $selectedXMLoutputType) {
                    ForEach(XMLOutputType.allCases) { outputType in
                        Text(outputType.rawValue) // Displays "EN", "FR"
                    }
                }                .pickerStyle(.segmented)
            }

        }
    }
}

#Preview {
    @Previewable @State var selectedXMLoutputType: XMLOutputType = .xml
    @Previewable @State var xmlAuthorName: String = ""
    @Previewable @State var xmlTitle: String = ""
    XMLSettingView(
        selectedXMLoutputType: $selectedXMLoutputType,
        xmlAuthorName: $xmlAuthorName,
        xmlTitle: $xmlTitle
    )
}


