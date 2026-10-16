//
//  PipelineSettingsView.swift
//  Tagger
//
//  Created by Adam on 08/09/2026.
//
// TOCHECK in downstream views
//        var showImporter: Bool
//        var hasAppeared: Bool
//        var isSelectingFolder: Bool
import SwiftUI
internal import UniformTypeIdentifiers

struct PipelineSettingsView: View {
    // input file
    @State var fileContainerModel = SourceFileContainerModel()
    @State var myConfig: TaggerConfig = TaggerConfig()
    @State var tempTokens: [TempToken] = []
        
    // reporting
    @State private var topLevelOutputList: [RunOutput] = []
    @State private var exportStatusMessage: String?
    @State private var runOutput: RunOutput?
    @State private var taggingInProgress: Bool = false
    // sentences ::
    @State var builtSents: [BuiltSentHolder] = []
    @State var sentsToRetokenise: [String] = []
    @State var exportContent: String = ""
    
    var unreadCount: Int {
        topLevelOutputList.reduce(0) { $1.runMetas.unread ? $0 + 1 : $0 }
    }
    #if DEBUG
    let runfive = false //
    #endif
  
    var body: some View {
        NavigationStack{
            Form {
                InputTypeEncapsulatorView(myConfig: $myConfig, fileContainerModel: $fileContainerModel)
                .accessibilityIdentifier("InputTypePicker")

                // First Picker
                Section("Parameters"){
                    InputFileViewEncapsulator(
                        myConfig: $myConfig,
                        builtSents: $builtSents,
                        tempTokens: $tempTokens,
                        fileContainerModel: fileContainerModel
                    )
                    Toggle(isOn: $myConfig.inputConfig.detectLanguage) {
                        Text("Autodetect Language")
                    }.onChange(of: myConfig.inputConfig.detectLanguage){_, newValue in
                        if newValue == true {
                            if let detectedLang = detectLangInFilename(inputURL:fileContainerModel.localSandboxFileURL){
                                myConfig.parsingConfig.selectedLanguage = detectedLang
                            }
                        }
                    }
                    .accessibilityIdentifier("DetectLanguageToggle")
                    
                    ConstrainedLanguagePickerView(title: "Language", selectedTreebankDefault: $myConfig.parsingConfig.selectedTreebank, selection: $myConfig.parsingConfig.selectedLanguage)
                        .onChange(of: fileContainerModel.localSandboxFileURL){
                            if myConfig.inputConfig.detectLanguage {
                                if let detectedLang = detectLangInFilename(inputURL:fileContainerModel.localSandboxFileURL){
                                    myConfig.parsingConfig.selectedLanguage = detectedLang
                                }
                            }
                        }
                        .accessibilityIdentifier("LanguagePicker")
                    
                    ConstrainedTreebankPickerView(title: "Treebank", selectedLang: $myConfig.parsingConfig.selectedLanguage, selectedTreebank: $myConfig.parsingConfig.selectedTreebank)
                        .accessibilityIdentifier("TreebankPicker")
                    
                    NavigationLink("Select processor steps"){
                        ProcessorStepConfigViewSection(myConfig: $myConfig)
                    }.accessibilityIdentifier("ProcessorStepLink")
                }
                // more sections::
                ExportConfigViewSection(myConfig: $myConfig)
                RunExplicitButtonView(myConfig: $myConfig)
                
                // MARK: the Go button
                Section {
                    BigGoButtonReadinessView(
                        isPipelineReady: isPipelineReady,
                        missingReqsMessage: missingRequirementsMessage
                    )
                    PipelineProgressView(myConfig: $myConfig)
                    Button(
                        action:{
                            runTagging(
                                inputFileType: myConfig.inputConfig.inputFileType,
                                maxPipelineStep: myConfig.parsingConfig.maxPipelineStep,
                                taggingInProgress: $taggingInProgress
                            ) // close runTagging bracket
                        } // close action brace
                    ) // close button bracket
                    {
                        TaggingProgressButtonView(taggingInProgress: taggingInProgress, isPipelineReady: isPipelineReady)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())
                    .controlSize(.large)
                    .disabled(taggingInProgress || !isPipelineReady)
                    .padding()

                } //close Go button section
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
            // default values on appear
            .accessibilityIdentifier("RunParsingButton")

            // MARK: toolbar :
            .toolbar{
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarLinkToOutputView(
                        myConfig: $myConfig,
                        topLevelOutputList: $topLevelOutputList,
                        builtSents: $builtSents,
                        tempTokens: $tempTokens,
                        unreadCount: unreadCount,
                        safeHeaderAttribs: myConfig.outputData.safeHeaderAttribs
                    )
                }
            }
        }
    }
    
    private func runTagging(
        inputFileType: InputFileType,
        maxPipelineStep: PipelineStep,
        taggingInProgress: Binding<Bool>) {
            
            // MARK: parameters, initialisations for task
            taggingInProgress.wrappedValue = true
//            startTime = nil
            myConfig.progressConfig.hasStarted = true
            myConfig.outputData.safeHeaderAttribs = makeSafeHeaderAttribs(myConfig: myConfig, fileContainerModel: fileContainerModel)
//            var resentencizerOutputStrings: [String] = []
//            var outSents: [Sentence] = []

            
            // MARK: tagging :
            Task {
                do {
                    // get pipeline object
                    let pipeline = try UDPipeline(myConfig: myConfig)
                    var allSentences: [HashableSentence] = []
                    
                    //MARK: INGEST SENTS ::
                    allSentences = try ingestSentEncapsulator(
                        myConfig: myConfig,
                        pipeline: pipeline
                    )
                    if myConfig.parsingConfig.runExplicit {
                        print("ingested sentences, n == \(allSentences.count).")
                    }
                    //MARK: check we have sents
                    guard !allSentences.isEmpty else {
                        taggingInProgress.wrappedValue = false
                        throw ParseProcessingError.noSentencesLoaded
                    }
                    //MARK: run resentenciser on request
                    if ![InputFileType.txt, InputFileType.manual].contains(myConfig.inputConfig.inputFileType) && myConfig.parsingConfig.runResentenciser{
                        myConfig.inputData.resentencizerOutputStrings = try desentenciseAndResentencise(
                            sentsToDiscard: allSentences,
                            myConfig: myConfig
                        )
                        myConfig.parsingConfig.runRetokeniser = true
                    }
                    
                    //MARK: run retokeniser if required/requested
                    if myConfig.inputConfig.inputFileType != .txt && myConfig.parsingConfig.runRetokeniser && [TokenizingMethod.nltokeniser, TokenizingMethod.trained].contains(myConfig.parsingConfig.tokenizingMethod) {
                        if myConfig.parsingConfig.runExplicit {
                            print("Retokenising")
                        }
                        allSentences = try retokenisationEncapsulator(
                            myConfig: myConfig,
                            pipeline: pipeline,
                            taggingInProgress: taggingInProgress
                        )
                    }

                    // optional chunk to test build-in NL parsing, send POS, lemmas to cols 8,9
                    if myConfig.parsingConfig.runExplicit{
                        var nlInputTexts: [String] = []
                        for sent in allSentences{
                            nlInputTexts.append(sent.tokens.joined(separator: " "))
                        }
                        for chunk in nlInputTexts{
                            let _ = getNLTags(text: chunk)
                        }
                    }

                    await MainActor.run {
                        myConfig.progressConfig.totalCount = allSentences.count
                        myConfig.progressConfig.appleProgress = Progress(totalUnitCount: Int64(max(allSentences.count, 1)))
                        myConfig.progressConfig.startTime = Date()
                    }

                    // MARK: Step 2: pass prepared data to parsing pipeline
#if DEBUG
                    if runfive {
                        allSentences = allSentences.count > 5 ? Array(allSentences.prefix(5)) : allSentences}
#endif
                    for sentence in allSentences {
                        let parsedTokens = try pipeline.runOnSentence(sentence, level: maxPipelineStep.rawValue)
                        myConfig.outputData.outSents.append(
                            postprocessSentence(sentence: sentence, parsedTokens: parsedTokens, myConfig: myConfig)
                        )
                        await MainActor.run {
                            myConfig.progressConfig.processedCount += 1
                            myConfig.progressConfig.appleProgress.completedUnitCount = Int64(myConfig.progressConfig.totalCount)
                        }
                    }
                    dumpDetailsForRunExplicit(myConfig: myConfig)
                    runOutput = makeTidyRunOutput(
                        outSents: myConfig.outputData.outSents, myConfig: myConfig,
                        safeHeaderAttribs: myConfig.outputData.safeHeaderAttribs
                    )
                    
                    if myConfig.parsingConfig.runExplicit {
                        guard let runOutput else {
                            taggingInProgress.wrappedValue = false
                            throw ParseProcessingError.noRunOutput
                        }
                        print(runOutput.runData.sents.generateExportText())
                    }
                    
                    try await MainActor.run {
                        taggingInProgress.wrappedValue = false
                        guard let runOutput else {
                            throw ParseProcessingError.noRunOutput
                        }
                        topLevelOutputList.append(runOutput)
                        if myConfig.parsingConfig.runExplicit{
                            print("topLevelOutputList length == \(topLevelOutputList.count)")
                        }
                    }
                } catch {
                    switch error {
                    case let parseProcessingError as ParseProcessingError:
                        myConfig.progressConfig.alertMessage = parseProcessingError.errorDescription
                    case let nsError as NSError where nsError.domain == XMLParser.errorDomain:
                        myConfig.progressConfig.alertMessage = "XML Parsing error : No valid XML to parse"
                    default:
                        myConfig.progressConfig.alertMessage = error.localizedDescription
                    }
                    await MainActor.run {
                        taggingInProgress.wrappedValue = false
                    }
                }
            }
        }
}

#Preview {
    PipelineSettingsView()
}

