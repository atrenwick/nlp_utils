//
//  PipelineSettingsView.swift
//  Tagger
//
//  Created by Adam on 08/09/2026.
//

import SwiftUI
internal import UniformTypeIdentifiers
import Combine

typealias PipelineKey = String
struct PipelineSettingsView: View {
    @Environment(AppModel.self) internal var model

    @AppStorage("buttonColor1Default") var buttonColor1DefaultData = Data()
    @AppStorage("buttonColor2Default") var buttonColor2DefaultData = Data()
    @State var buttonColor1: Color = .yellow
    @State var buttonColor2: Color = .orange
    
    @State internal var isLoading = false
    @State internal var loadedCount = 1
    @State internal var loadStatus = ""
    @State internal var taggingInProgress: Bool = false
    @State var isFirstRun: Bool = true
    @State var pipelineSummary: String = ""
    @State var currentStatus: String = ""
    @State var sentsToRetokenise: [String] = []
    @State var exportContent: String = ""
    @State var currentPipelineLoaded: Bool = false
    @State var currentPipelineDesc: PipelineDesc?
    @State var showInterruptButton: Bool = false
    @State var interruptSignalled: Bool = false
    @State var loadedPipelines: [PipelineHelper] = [ ]
    
    var unreadCount: Int {
        model.allRunOutputs.reduce(0) { $1.runMetas.unread ? $0 + 1 : $0 }
    }
    
    var bigButtonColor: Color {
        if model.pipelineCache.isLive{
            return buttonColor1
        } else {
            return buttonColor2
        }
    }
    
    var previousRun: [RunOutput] {
        if model.allRunOutputs.count == 0 {
            return []
        } else if model.allRunOutputs.count == 1 {
            return model.allRunOutputs
        } else {
            let sorted = model.allRunOutputs.sorted {$0.runMetas.safeHeaderAttribs.taggingDate < $1.runMetas.safeHeaderAttribs.taggingDate}
            if let mostRecent = sorted.last{
                return [mostRecent]
            } else {
                return []
            }
        }
    }
    var previousResumable: Bool{
        if previousRun.count >= 1  && previousRun[0].runMetas.processingStatus.interruptRequested == "True" {
            return true
        } else {
            return false
        }
    }
#if DEBUG
    let runfive = false //
#endif
    var body: some View {
        @Bindable var model = model

        NavigationStack{
            Form {
                InputTypeExtractedView()
                    .accessibilityIdentifier("InputTypePicker")
                
                // First Picker
                Section("Parameters"){
                    InputFileViewEncapsulator()
                    MatchDetectToggleView()
                    ArchitecturePickerView()
                    ConstrainedPickerForLang()
                    ConstrainedPickerForTB()
                    NavigationLink("Select processor steps"){ ProcessorStepConfigViewSection() }
                    NavigationLink("Define offsets"){ TaggingOffsetParamsView() }
                }
                
                NavigationLink(destination:
                                MultiParseConfigurationView()){
                    HStack{
                        Text("Multiparses")
                        Spacer()
                        Image(systemName: "\(model.myConfig.parsingConfig.pipelineRequests.count).circle.fill" )
                    }.foregroundStyle( model.currentMode == .multi ? .green : .blue )
                }

                ExportConfigViewSection()
                //#if debug
                //                RunExplicitButtonExtractedView(myConfig: $myConfig)
                //#endif
                
                // MARK: the Go button
                Section{
                    Group{
                        GoSectionUpperHalf(
                            currentStatus: $currentStatus,
                            isLoading: $isLoading,
                            loadedCount: $loadedCount,
                            loadStatus: $loadStatus,
                            myConfig: $model.myConfig,
                            isPipelineReady: isPipelineReady,
                            loadTotal: loadTotal,
                            missingReqsMessage: missingReqsMessage,
                        )
                        Button {
                            runTagging(
                                taggingInProgress: $taggingInProgress,
                                isFirstRun: $isFirstRun,
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
                        .tint(bigButtonColor)
                        .clipShape(Capsule())
                        .controlSize(.large)
                        .disabled(taggingInProgress || !isPipelineReady)
                        .padding()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if taggingInProgress || 1 == 1 {
                            Button("Stop") {
                                showInterruptButton = true
                            }
                            .tint(.red)
                        }
                    }
                    .confirmationDialog(
                        "Interrupt",
                        isPresented: $showInterruptButton,
                        titleVisibility: .visible
                    ){
                        Button("Stop", role: .destructive){
                            interruptSignalled = true
                            model.myConfig.progressConfig.processingStatus = .interrupted
                        }
                        Button("Cancel", role: .cancel){ }
                    } message: {
                        Text("Items processed so far will be kept")
                    }
                    .alert("Error !",
                           isPresented: Binding(
                            get: {model.myConfig.progressConfig.alertMessage != nil},
                            set: {if !$0 {model.myConfig.progressConfig.alertMessage = nil} } )
                    ) { Button("OK", role: .cancel) { }
                    } message: { Text(model.myConfig.progressConfig.alertMessage ?? "") }
                }
            }
            .accessibilityIdentifier("RunParsingButton")
            
            // MARK: toolbar :
            .toolbar{
                if model.myConfig.inputData.builtSents.count > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        ManualTokenisationToolbarItem()
                    }
                }
            }
        }
        .onAppear(perform: loadButtonColours)
    }
}

#Preview {
    PipelineSettingsView().environment(AppModel())
}
