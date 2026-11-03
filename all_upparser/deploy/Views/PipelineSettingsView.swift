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
    @State var showInterruptButton: Bool = false
    @State var interruptSignalled: Bool = false
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
                    
                    MatchDetectToggleView(myConfig: $myConfig, fileContainerModel: $fileContainerModel)
                    ArchitecturePickerView(myConfig: $myConfig)
                    ConstrainedPickerForLang(myConfig: $myConfig)
                    ConstrainedPickerForTB(myConfig: $myConfig)
                    NavigationLink("Select processor steps"){
                        ProcessorStepConfigViewSection(myConfig: $myConfig)
                    }
                }

                ExportConfigViewSection(myConfig: $myConfig)
                //#if debug
                //                RunExplicitButtonExtractedView(myConfig: $myConfig)
                //#endif
                // MARK: the Go button
                Section {

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
                    Button {
                            runTagging(
                                inputFileType: myConfig.inputConfig.inputFileType,
                                maxPipelineStep: myConfig.parsingConfig.maxPipelineStep,
                                taggingInProgress: $taggingInProgress,
                                isFirstRun: $isFirstRun
                            )
                    } label: {
                        TaggingProgressButtonExtractedView(
                            taggingInProgress: taggingInProgress,
                            isPipelineReady: isPipelineReady,
                            pipelineSummary: pipelineSummary,
                            currentPipelineDesc: $currentPipelineDesc,
                            currentPipelineLoaded: $currentPipelineLoaded
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())
                    .controlSize(.large)
                    .disabled(taggingInProgress || !isPipelineReady)
                    .padding()
                    
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if taggingInProgress {
                                Button("Stop") {
                                    showInterruptButton = true
                                }
                                .tint(.red)
                            }
                        }
                .confirmationDialog("Interrupt"
                                    , isPresented: $showInterruptButton, titleVisibility: .visible){
                    Button("Stop", role: .destructive){
                            interruptSignalled = true
                    }
                    Button("Cancel", role: .cancel){ }
                } message: {
                    Text("Items processed so far will be kept")
                     }
                
                .alert("Error !",
                    isPresented: Binding(
                        get: {myConfig.progressConfig.alertMessage != nil},
                        set: {if !$0 {myConfig.progressConfig.alertMessage = nil} } )
                ) { Button("OK", role: .cancel) { }
                } message: { Text(myConfig.progressConfig.alertMessage ?? "") }
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


