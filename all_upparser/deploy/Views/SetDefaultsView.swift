//
//  SetDefaultsView.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
//

import SwiftUI
import NaturalLanguage

struct SetDefaultsView: View {
	
    //input file
    @AppStorage("inputTypeDefault") private var inputFileTypeDefault: InputFileType = .txt

    //import + parsing settings
    @AppStorage("detectLangDefault") var detectLangDefault: Bool = false
    @AppStorage("selectedLanguageDefault") var selectedLanguageDefault: Language = .FR
    @AppStorage("selectedTreebankDefault") var selectedTreebankDefault: Language.Treebank = .frTB3
    @AppStorage("tokenizingMethodDefault") var tokenizingMethodDefault: TokenizingMethod = .nltokeniser
    @AppStorage("sentencizingMethodDefault")  var sentencizingMethodDefault: SentencizingMethod = .nlSentencizer
    @AppStorage("maxPipelineStepDefault")  var maxPipelineStepDefault: PipelineStep = .step5

    //export
    @AppStorage("selectedExportFormatDefault")  var selectedExportFormatDefault: ExportFormat = .xml
    @AppStorage("xmlAuthorDefault")  var xmlAuthorDefault: String = "XML Author"
    @AppStorage("xmlTitleDefault")  var xmlTitleDefault: String = "XML Title"
    @AppStorage("fileNameDefault") var fileNameDefault: String = "fileName"
    
    @State var sentences: [String] = []



    var body: some View {
        VStack{
            Form{
                Section("Source file"){
                    Toggle(isOn: $detectLangDefault){
                        Text("Autodetect lang in filename")
                    }
                    Picker("InputFiletype", selection: $inputFileTypeDefault){
                        ForEach(InputFileType.allCases){type in
                            Text(type.rawValue)}
                    }
                }
                Section("Processing"){
                    Picker("Default language", selection: $selectedLanguageDefault){
                        ForEach(Language.allCases){lang in
                            Text(lang.displayName.uppercased())
                        }
                    }
                    .onChange(of: selectedLanguageDefault) { _, newLang in
                        if let first = newLang.availableTBs.first {
                            selectedTreebankDefault = first
                        }
                    }

                    Picker("Treebank", selection: $selectedTreebankDefault){
                        ForEach(selectedLanguageDefault.availableTBs){tb in
                            Text(tb.short).tag(tb)
                        }
                    }
                    .onChange(of: selectedLanguageDefault) { _, newLang in
                        // Automatically update selected tb to language default
                        selectedTreebankDefault = newLang.defaultTB
                    }

                    Picker("Tokenisation method", selection: $tokenizingMethodDefault){
                        ForEach(TokenizingMethod.allCases){method in
                            Text(method.rawValue)
                        }
                    }
                    Picker("Sentencization method", selection: $sentencizingMethodDefault){
                        ForEach(SentencizingMethod.allCases){method in
                            Text(method.rawValue)
                        }
                    }
                    Picker("Max pipeline step", selection: $maxPipelineStepDefault){
                        ForEach(PipelineStep.allCases){step in
                            Text(step.title)
                        }
                    }

                }
                Section("Output file"){
                    TextField("Filename", text: $fileNameDefault)
                    Picker("Export format", selection: $selectedExportFormatDefault){
                        ForEach(ExportFormat.allCases){format in
                            Text(format.rawValue)
                        }
                    }
                    TextField("XML Title", text: $xmlTitleDefault)

                    TextField("XML Author", text: $xmlAuthorDefault)
                    }
            }
        }
    }
}



#Preview {
    SetDefaultsView()
}

