//
//  SetDefaultsView.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
//

import SwiftUI
import NaturalLanguage
internal import UniformTypeIdentifiers

struct SetDefaultsView: View {
    @AppStorage("runExplicitDefault")  var runExplicitDefault: Bool = false
    
    //input file
    @AppStorage("inputTypeDefault") private var inputFileTypeDefault: InputFileType = .txt

    //import + parsing settings
    @AppStorage("detectLangDefault") var detectLangDefault: Bool = true
    @AppStorage("selectedLanguageDefault") var selectedLanguageDefault: Language = .FR
    @AppStorage("selectedTreebankDefault") var selectedTreebankDefault: Language.Treebank = .frTB3
    @AppStorage("tokenizingMethodDefault") var tokenizingMethodDefault: TokenizingMethod = .nltokeniser
    @AppStorage("sentencizingMethodDefault")  var sentencizingMethodDefault: SentencizingMethod = .nlSentencizer
    @AppStorage("maxPipelineStepDefault")  var maxPipelineStepDefault: PipelineStep = .step5
    @AppStorage("insertNewTokPositionDefault") var insertNewTokPositionDefault: InsertPosition = .after
    @AppStorage("runRetokeniserDefault") var runRetokeniserDefault: Bool = false
    @AppStorage("runResentenciserDefault")  var runResentenciserDefault: Bool = false
    @AppStorage("progressBarStyleDefault") var progressBarStyleDefault: ProgressBarStyle = .apple
    @AppStorage("retokenisationTypeDefault") var retokenisationTypeDefault: RetokenisationType = .predict

    //export
    @AppStorage("xmlAuthorDefault")  var xmlAuthorDefault: String = "XML Author"
    @AppStorage("xmlTitleDefault")  var xmlTitleDefault: String = "XML Title"
    @AppStorage("fileNameDefault") var fileNameDefault: String = makeFilename() //"fileName"
    @AppStorage("selectedExportFormatDefault")  var selectedExportFormatDefault: ExportFormat = .xml
    @AppStorage("includeConllSentIdLineDefault") var includeConllSentIdLineDefault: Bool = true
    @AppStorage("includeConllSentTextDefault") var includeConllSentTextDefault: Bool = true
    @AppStorage("outputDirDefault") var outputDirDefault: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
    @State var sentences: [String] = []
    @State var isSelectingFolder: Bool = false
    
    var body: some View {
        
        VStack{
            Form{
                Section{
                    Toggle(isOn: $runExplicitDefault){
                        Text("Verbose Mode")
                    }
                }
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
                        selectedTreebankDefault = newLang.defaultTB
                    }
                    Picker("Max pipeline step", selection: $maxPipelineStepDefault){
                        ForEach(PipelineStep.allCases){step in
                            Text(step.title)
                        }
                    }
                }
                Section("Tokenisation"){
                    Toggle(isOn: $runRetokeniserDefault){
                        Text("Retokenise by default")
                    }
                    Picker("Tokenisation method", selection: $tokenizingMethodDefault){
                        ForEach(TokenizingMethod.allCases){method in
                            Text(method.rawValue)
                        }
                    }
                    Picker("Insert new token position", selection: $insertNewTokPositionDefault){
                        ForEach(InsertPosition.allCases){position in
                            Text(position.rawValue)}
                    }
                }
                Section("Sentencization"){
                    Picker("Sentencization method", selection: $sentencizingMethodDefault){
                        ForEach(SentencizingMethod.allCases){method in
                            Text(method.rawValue)
                        }
                    }
                    Toggle(isOn: $runResentenciserDefault){
                        Text("Resentencise by default")
                    }
                }
                Section("View"){
                    Picker("Progress bar style", selection: $progressBarStyleDefault){
                        ForEach(ProgressBarStyle.allCases){style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                }
                Section("Output file"){
                    TextField("Filename", text: $fileNameDefault)
                    HStack{
                        Text("Output dir")
                            Spacer()
                        Text(outputDirDefault.lastPathComponent ?? "Not Selected")
                            .foregroundColor(.secondary)
                        Button("Choose...") {
                            isSelectingFolder = true
                        }
                    }
                    Picker("Export format", selection: $selectedExportFormatDefault){
                        ForEach(ExportFormat.allCases){format in
                            Text(format.rawValue)
                        }
                    }
                    TextField("XML Title", text: $xmlTitleDefault)
                    TextField("XML Author", text: $xmlAuthorDefault)
                    Toggle(isOn: $includeConllSentIdLineDefault){
                        Text("Include metaline # sent_id = ")
                    }
                    Toggle(isOn: $includeConllSentTextDefault){
                        Text("Include metaline # sent_text = ")
                    }
                }
                .fileImporter(
                    isPresented: $isSelectingFolder,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            // Gain security access to folder
                            if url.startAccessingSecurityScopedResource() {
                                outputDirDefault = url
                            }
                        }
                    case .failure(let error):
                        print("Folder selection error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

#Preview {
    SetDefaultsView()
}

