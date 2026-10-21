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
    @AppStorage("matchFileNameTypeDefault") var matchFileNameTypeDefault: Bool = false
    @AppStorage("selectedLanguageDefault") var selectedLanguageDefault: Language = .FR
    @AppStorage("selectedTreebankDefault") var selectedTreebankDefault: Language.Treebank = .frTB3
    @AppStorage("selectedArchitectureDefault") var selectedArchitectureDefault: ModelArchitecture = .cnnBiLSTM

    @AppStorage("bertlikeTokMethodFailoverDefault") var bertlikeTokMethodFailoverDefault: TokenizingMethod = .nltokeniser


    
    @AppStorage("tokenizingMethodDefault") var tokenizingMethodDefault: TokenizingMethod = .nltokeniser
    @AppStorage("sentencizingMethodDefault")  var sentencizingMethodDefault: SentencizingMethod = .nlSentencizer
    @AppStorage("maxPipelineStepDefault")  var maxPipelineStepDefault: PipelineStep = .step5
    @AppStorage("insertNewTokPositionDefault") var insertNewTokPositionDefault: InsertPosition = .after
    @AppStorage("runRetokeniserDefault") var runRetokeniserDefault: Bool = false
    @AppStorage("runResentenciserDefault")  var runResentenciserDefault: Bool = false
    @AppStorage("progressBarStyleDefault") var progressBarStyleDefault: ProgressBarStyle = .apple
    @AppStorage("retokenisationTypeDefault") var retokenisationTypeDefault: RetokenisationType = .predict
    @AppStorage("modelArchitectureDefault") var modelArchitectureDefault: ModelArchitecture = .cnnBiLSTM

    @AppStorage("priLemSourceDefault") var priLemSourceDefault: LemmaSource = .hybrid
    @AppStorage("secLemSourceDefault") var secLemSourceDefault: LemmaSource = .rule
    @AppStorage("getSecLemsDefault") var getSecLemsDefault: Bool = false


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
                    Toggle(isOn: $matchFileNameTypeDefault){Text("Automatch filename-type")}
                    Toggle(isOn: $detectLangDefault){ Text("Autodetect lang in filename")}
                    DefaultPickerView(title: "InputFiletype method", selection: $inputFileTypeDefault)
                }
                Section("Processing"){
                    Picker("modelArchitectureDefault", selection: $modelArchitectureDefault){
                        ForEach(ModelArchitecture.allCases){modArch in
                            Text(modArch.displayName)
                        }
                    }
                    ConstrainedLanguagePickerView(
                        title: "Treebank",
                        selectedTreebankDefault: $selectedTreebankDefault,
                        selection: $selectedLanguageDefault,
                        selectedArchitecture: $selectedArchitectureDefault
                )
                    
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
                    DefaultPickerView(title: "Tokenisation method", selection: $tokenizingMethodDefault)
                    DefaultPickerView(title: "Insert new token position", selection: $insertNewTokPositionDefault)
                }
                Section("Sentencization"){
                    DefaultPickerView(title: "Sentencization method", selection: $sentencizingMethodDefault)
                    DefaultPickerView(title: "BERT-like TXT sentencizer", selection: $bertlikeTokMethodFailoverDefault)
                    Toggle(isOn: $runResentenciserDefault){ Text("Resentencise by default") }
                }
                Section("Lemmatization"){
                    Toggle(isOn: $getSecLemsDefault){ Text("Get Secondary lemmas if avail.") }
                    Picker("Primary method", selection: $priLemSourceDefault){
                        ForEach(LemmaSource.allCases){lsource in
                            Text(lsource.displayName)
                        }
                    }
                    .onChange(of: secLemSourceDefault){_, newValue in
                        if secLemSourceDefault == priLemSourceDefault {
                            if let remaining = LemmaSource.allCases.filter({ format in format != secLemSourceDefault  }).first{
                                priLemSourceDefault = remaining
                            }
                        }
                    }
                    Picker("Secondary method", selection: $secLemSourceDefault){
                        ForEach(LemmaSource.allCases){lsource in
                            Text(lsource.displayName)
                        }
                    }
                    .onChange(of: priLemSourceDefault){_, newValue in
                        if secLemSourceDefault == priLemSourceDefault {
                            if let remaining = LemmaSource.allCases.filter({ format in format != priLemSourceDefault  }).first{
                                secLemSourceDefault = remaining
                            }
                        }
                    }
                }
                Section("View"){
                    DefaultPickerView(title: "Progress bar style", selection: $progressBarStyleDefault)
                }
                Section("Output file"){
                    TextField("Filename", text: $fileNameDefault)
                    HStack{
                        Text("Output dir")
                            Spacer()
                        Text(outputDirDefault.lastPathComponent)
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

