//
//  BertPipelineSettingsTestView.swift
//  Tagger
//
//  Created by Adam on 20/10/2026.
//

import SwiftUI
internal import UniformTypeIdentifiers



//struct BertPipelineSettingsTestView: View {
//    // input file
//    @State var fileContainerModel = SourceFileContainerModel()
//    @State var myConfig: TaggerConfig = TaggerConfig()
//    @State var tempTokens: [TempToken] = []
//    
//    // reporting
//    @State private var topLevelOutputList: [RunOutput] = []
//    @State private var exportStatusMessage: String?
//    @State private var runOutput: RunOutput?
//    @State private var taggingInProgress: Bool = false
//    @State var isFirstRun: Bool = true
//    // sentences ::
//    @State var builtSents: [BuiltSentHolder] = []
//    @State var sentsToRetokenise: [String] = []
//    @State var exportContent: String = ""
//    
//    var availableLanguages: [Language] {
//            ConfigurationRules.availableLanguages(for: myConfig.parsingConfig.modelArchitecture)
//        }
//
//    var availableTreebanks: [Language.Treebank] {
//            ConfigurationRules.availableTreebanks(for: myConfig.parsingConfig.modelArchitecture, language: myConfig.parsingConfig.selectedLanguage)
//        }
//    
//    var unreadCount: Int {
//        topLevelOutputList.reduce(0) { $1.runMetas.unread ? $0 + 1 : $0 }
//    }
//#if DEBUG
//    let runfive = false //
//#endif
//    
//    var body: some View {
//        NavigationStack{
//            Form {
//                InputTypeEncapsulatorView(myConfig: $myConfig, fileContainerModel: $fileContainerModel)
//                .accessibilityIdentifier("InputTypePicker")
//
//                // First Picker
//                Section("Parameters"){
//                    InputFileViewEncapsulator(
//                        myConfig: $myConfig,
//                        builtSents: $builtSents,
//                        tempTokens: $tempTokens,
//                        fileContainerModel: fileContainerModel
//                    )
//                    Toggle(isOn: $myConfig.inputConfig.detectLanguage) {
//                        Text("Autodetect Language")
//                    }.onChange(of: myConfig.inputConfig.detectLanguage){_, newValue in
//                        if newValue == true {
//                            if let detectedLang = detectLangInFilename(inputURL:fileContainerModel.localSandboxFileURL){
//                                myConfig.parsingConfig.selectedLanguage = detectedLang
//                            }
//                        }
//                    }
//                    .accessibilityIdentifier("DetectLanguageToggle")
//                    
//                    Picker("architecture", selection: $myConfig.parsingConfig.modelArchitecture){
//                        ForEach(ModelArchitecture.allCases){modarch in
//                            Text(modarch.displayName)
//                        }
//                    }.onChange(of: myConfig.parsingConfig.modelArchitecture)
//                    {if myConfig.parsingConfig.modelArchitecture == .distilbert {
//                        myConfig.parsingConfig.selectedLanguage = .FR
//                        myConfig.parsingConfig.selectedTreebank = .frTB1
//                        
//                    }}
//                    
//                    ConstrainedLanguagePickerView(title: "Language", selectedTreebankDefault: $myConfig.parsingConfig.selectedTreebank, selection: $myConfig.parsingConfig.selectedLanguage, selectedArchitecture: $myConfig.parsingConfig.selectedArchitecture)
//                        .onChange(of: fileContainerModel.localSandboxFileURL){
//                            if myConfig.inputConfig.detectLanguage {
//                                if let detectedLang = detectLangInFilename(inputURL:fileContainerModel.localSandboxFileURL){
//                                    myConfig.parsingConfig.selectedLanguage = detectedLang
//                                }
//                            }
//                        }
//                        .accessibilityIdentifier("LanguagePicker")
//                    
//                    ConstrainedTreebankPickerView(title: "Treebank", selectedLang: $myConfig.parsingConfig.selectedLanguage, selectedTreebank: $myConfig.parsingConfig.selectedTreebank, selectedArchitecture: $myConfig.parsingConfig.selectedArchitecture)
//                        .accessibilityIdentifier("TreebankPicker")
//                    
//                    NavigationLink("Select processor steps"){
//                        ProcessorStepConfigViewSection(myConfig: $myConfig)
//                    }.accessibilityIdentifier("ProcessorStepLink")
//                }
//                // more sections::
//                ExportConfigViewSection(myConfig: $myConfig)
//                RunExplicitButtonView(myConfig: $myConfig)
//                
//                // MARK: the Go button
//                Section {
//                    BigGoButtonReadinessView(
//                        isPipelineReady: isPipelineReady,
//                        missingReqsMessage: missingRequirementsMessage
//                    )
//                    PipelineProgressView(myConfig: $myConfig)
//                    Button(
//                        action:{
//                            print("run tagging")
//                            
//                        } // close action brace
//                    ) // close button bracket
//                    {
//                        TaggingProgressButtonView(taggingInProgress: taggingInProgress, isPipelineReady: isPipelineReady)
//                    }
//                    .buttonStyle(.borderedProminent)
//                    .clipShape(Capsule())
//                    .controlSize(.large)
//                    .disabled(taggingInProgress || !isPipelineReady)
//                    .padding()
//
//                } //close Go button section
//                .alert(
//                    " Error",
//                    isPresented: Binding(
//                        get: {myConfig.progressConfig.alertMessage != nil},
//                        set: {if !$0 {myConfig.progressConfig.alertMessage = nil}}
//                    )
//                )
//                {
//                    Button("OK", role: .cancel) { }
//                } message: {
//                    Text(myConfig.progressConfig.alertMessage ?? "")
//                }
//            }
//            // default values on appear
//            .accessibilityIdentifier("RunParsingButton")
//
//            // MARK: toolbar :
//            .toolbar{
//                ToolbarItem(placement: .topBarTrailing) {
//                    ToolbarLinkToOutputView(
//                        myConfig: $myConfig,
//                        topLevelOutputList: $topLevelOutputList,
//                        builtSents: $builtSents,
//                        tempTokens: $tempTokens,
//                        unreadCount: unreadCount,
//                        safeHeaderAttribs: myConfig.outputData.safeHeaderAttribs
//                    )
//                }
//            }
//        }
//    }
//    // copies from pipelineSettingsViewExtension
//    var missingRequirements: [String] {
//        var missing: [String] = []
//        
//        // Rule 1: Check input file exists in sandbox
//        if fileContainerModel.localSandboxFileURL == nil && myConfig.inputConfig.inputFileType != .manual{
//            missing.append("Input File")
//        }
//        
//        let ext = fileContainerModel.localSandboxFileURL?.pathExtension ?? "nil"
//        if  myConfig.inputConfig.inputFileType.allowedReadExt.contains(ext) == false  && myConfig.inputConfig.inputFileType != .manual {
//            missing.append("extension-InputType Mismatch")
//        }
//        
//        if myConfig.inputConfig.inputFileType == .manual && builtSents.count == 0 {
//            missing.append("No built sents found")
//        }
//        
//        // Rule 2: Check custom output filename is typed
//        if myConfig.exportConfig.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//            missing.append("Output Filename")
//        }
//        
//        // Rule 3: Check target folder (or destination setting)
//        if myConfig.exportConfig.targetFolderURL == nil {
//            missing.append("Export Directory")
//        }
//        
//        return missing
//    }
//    
//    // 2. Boolean check for the .disabled() modifier
//    var isPipelineReady: Bool {
//        return missingRequirements.isEmpty
//    }
//    
//    // 3. User-friendly warning message
//    var missingRequirementsMessage: String {
//        guard !missingRequirements.isEmpty else { return "" }
//        
//        if missingRequirements.count == 1 {
//            return "Set: \(missingRequirements[0])"
//        } else {
//            // Lists items cleanly: "Missing required settings: Input File, Output Filename, Export Directory"
//            return "Missing required settings: \(missingRequirements.joined(separator: ", "))"
//        }
//    }
//    
//}

    
    
//}

//#Preview {
//    BertPipelineSettingsTestView()
//}
