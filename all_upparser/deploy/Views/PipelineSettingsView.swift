//
//  PipelineSettingsView.swift
//  Tagger
//
//  Created by Adam on 08/09/2026.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct PipelineSettingsView: View {
    // input file
    @State var fileContainerModel = SourceFileContainerModel()
    @State var myConfig: TaggerConfig = TaggerConfig()
    @State var tempTokens: [TempToken] = []
    // reporting
    @State internal var isLoading = false
    @State internal var loadedCount = 1
    @State internal var loadStatus = ""
    @State internal var allRunOutputs: [RunOutput] = []
    @State internal var exportStatusMessage: String?
    @State internal var runOutput: RunOutput?
    @State internal var taggingInProgress: Bool = false
    @State var isFirstRun: Bool = true
    @State var pipelineSummary: String = ""
    @State var currentStatus: String = ""
    // sentences ::
    @State var builtSents: [BuiltSentHolder] = []
    @State var sentsToRetokenise: [String] = []
    @State var exportContent: String = ""
    @State var currentPipelineLoaded: Bool = false
    @State var currentPipelineDesc: PipelineDesc?

    var unreadCount: Int {
        allRunOutputs.reduce(0) { $1.runMetas.unread ? $0 + 1 : $0 }
    }
#if DEBUG
    let runfive = false //
#endif
    
    var body: some View {
        NavigationStack{
            Form {
                InputTypeExtractedView(myConfig: $myConfig, fileContainerModel: $fileContainerModel)
                    .accessibilityIdentifier("InputTypePicker")
                
                // First Picker
                Section("Parameters"){
                    InputFileViewEncapsulator(
                        myConfig: $myConfig,
                        builtSents: $myConfig.inputData.builtSents,
                        tempTokens: $tempTokens,
                        fileContainerModel: fileContainerModel
                    )
                    
                    Toggle(isOn: $myConfig.inputConfig.detectLanguage) {
                        Text("Autodetect Language")
                    }.onChange(of: myConfig.inputConfig.detectLanguage){_, newValue in
                        if newValue == true, let detectedLang =  FileIngestionWorkflow.detectLangInFilename(inputURL:fileContainerModel.localSandboxFileURL){
                            myConfig.parsingConfig.selectedLanguage = detectedLang
                        } else {print("case 3")}
                    }
                    .accessibilityIdentifier("DetectLanguageToggle")
                    
                    Toggle(isOn: $myConfig.inputConfig.matchFileNameType) {
                        Text("Automatch filename-type")
                    }.onChange(of: myConfig.inputConfig.matchFileNameType){_, newValue in
                        if newValue == true, let detectedValue = fileContainerModel.localSandboxFileURL?.pathExtension {
                            if let convertedExt = InputFileType(rawValue: detectedValue.replacingOccurrences(of: ".", with: "")){
                                myConfig.inputConfig.inputFileType = convertedExt
                            }
                        }
                    }
                    
                    Picker("Architecture", selection: $myConfig.parsingConfig.modelArchitecture){
                        ForEach(ModelArchitecture.allCases.sorted {$0.rawValue < $1.rawValue }){modarch in
                            Text(modarch.displayName)
                        }
                    }.onChange(of: myConfig.parsingConfig.modelArchitecture){
                        if myConfig.parsingConfig.modelArchitecture == .distilbert && myConfig.inputConfig.inputFileType == .txt {myConfig.parsingConfig.tokenizingMethod = .nltokeniser}
                    }
                    ConstrainedPickerForLang(myConfig: $myConfig)
                        .accessibilityIdentifier("LanguagePicker")
                    ConstrainedPickerForTB(myConfig: $myConfig)
                        .accessibilityIdentifier("TreebankPicker")
                    NavigationLink("Select processor steps"){
                        ProcessorStepConfigViewSection(myConfig: $myConfig)
                    }.accessibilityIdentifier("ProcessorStepLink")
                }

                ExportConfigViewSection(myConfig: $myConfig)
                //#if debug
                //                RunExplicitButtonExtractedView(myConfig: $myConfig)
                //#endif
                // MARK: the Go button
                Section {
                    var myNum: Int = 0
                    GoSectionUpperHalf(
                        myConfig: $myConfig,
                        currentStatus: $currentStatus,
                        isPipelineReady: isPipelineReady,
                        missingReqsMessage: missingReqsMessage,
                        isLoading: $isLoading,
                        loadTotal: loadTotal,
                        loadedCount: $loadedCount,
                        loadStatus: $loadStatus
                    )
                    Button(
                        action:{
                            runTagging(
                                inputFileType: myConfig.inputConfig.inputFileType,
                                maxPipelineStep: myConfig.parsingConfig.maxPipelineStep,
                                taggingInProgress: $taggingInProgress,
                                isFirstRun: $isFirstRun
                            )
                            myNum += 1
                        }
                    )
                    {
                        TaggingProgressButtonExtractedView(taggingInProgress: taggingInProgress, isPipelineReady: isPipelineReady, pipelineSummary: pipelineSummary, currentPipelineDesc: $currentPipelineDesc, currentPipelineLoaded: $currentPipelineLoaded)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())
                    .controlSize(.large)
                    .disabled(taggingInProgress || !isPipelineReady)
                    .padding()
                    
                }
                .alert(
                    " Error",
                    isPresented: Binding(
                        get: {myConfig.progressConfig.alertMessage != nil},
                        set: {if !$0 {myConfig.progressConfig.alertMessage = nil}}
                    )
                )
                {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(myConfig.progressConfig.alertMessage ?? "")
                }
            }
            .accessibilityIdentifier("RunParsingButton")
            
            // MARK: toolbar :
            .toolbar{
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarLinkToOutputExtractedView(
                        myConfig: $myConfig,
                        allRunOutputs: $allRunOutputs,
                        builtSents: $builtSents,
                        tempTokens: $tempTokens,
                        unreadCount: unreadCount,
                        safeHeaderAttribs: myConfig.outputData.safeHeaderAttribs
                    )
                }
            }
        }
    }
}

#Preview {
    PipelineSettingsView()
}


