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
    @State private var topLevelOutputList: [RunOutput] = []
    @State private var exportStatusMessage: String?
    @State private var runOutput: RunOutput?
    @State private var taggingInProgress: Bool = false
    @State var isFirstRun: Bool = true
    @State var pipelineSummary: String = ""
    @State var currentStatus: String = ""
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
                // watch this with $matchFileNameTypeDefault

                // First Picker
                Section("Parameters"){
                    InputFileViewEncapsulator(
                        myConfig: $myConfig,
                        builtSents: $myConfig.inputData.builtSents,
                        tempTokens: $tempTokens,
                        fileContainerModel: fileContainerModel
                    )
                    // watch this with $matchFileNameTypeDefault

                    HStack{
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
                        Toggle(isOn: $myConfig.inputConfig.matchFileNameType) {
                            Text("Automatch filename-type")
                        }.onChange(of: myConfig.inputConfig.matchFileNameType){_, newValue in
                            if newValue == true {
                                //do this
                                if let detectedValue = fileContainerModel.localSandboxFileURL?.pathExtension {
                                    if let convertedExt = InputFileType(rawValue: detectedValue.replacingOccurrences(of: ".", with: "")){
                                        myConfig.inputConfig.inputFileType = convertedExt
                                    }
                                }
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
                // more sections::
                ExportConfigViewSection(myConfig: $myConfig)
//#if debug
//                RunExplicitButtonView(myConfig: $myConfig)
//#endif
                // MARK: the Go button
                Section {
                    var myNum: Int = 0
                    BigGoButtonReadinessView(
                        isPipelineReady: isPipelineReady,
                        missingReqsMessage: missingRequirementsMessage
                    )
                    PipelineProgressView(myConfig: $myConfig, currentStatus: $currentStatus)
                    Button(
                        action:{
                            runTagging(
                                inputFileType: myConfig.inputConfig.inputFileType,
                                maxPipelineStep: myConfig.parsingConfig.maxPipelineStep,
                                taggingInProgress: $taggingInProgress,
                                isFirstRun: $isFirstRun
                            )
                            myNum += 1
                            // close runTagging bracket
                        } // close action brace
                    ) // close button bracket
                    {
                        TaggingProgressButtonView(taggingInProgress: taggingInProgress, isPipelineReady: isPipelineReady, pipelineSummary: pipelineSummary)
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
        taggingInProgress: Binding<Bool>,
        isFirstRun: Binding<Bool>
    ) {

        if !isFirstRun.wrappedValue {
            myConfig.runResetters()
        } else {
            isFirstRun.wrappedValue = false
        }
        // MARK: parameters, initialisations for task
            myConfig.parsingConfig.runExplicit = true
            taggingInProgress.wrappedValue = true
            myConfig.progressConfig.hasStarted = true
            myConfig.outputData.safeHeaderAttribs = makeSafeHeaderAttribs(myConfig: myConfig, fileContainerModel: fileContainerModel)

            // MARK: tagging :
            Task {
                do {
                    // get pipeline object
                    var allSentences: [HashableSentence] = []
                    let pipeline: PipelineHelper
                    currentStatus = "Loading pipeline"
                    switch myConfig.parsingConfig.modelArchitecture {
                    case .distilbert:
                        pipeline = try BERTlikePipeline(myConfig: myConfig, version: 2)
                        print("bert pipeline called")
                    case .cnnBiLSTM:
                        pipeline = try CNNBiLSTMPipeline(myConfig: myConfig)
                        print("cnn-lstm pipeline called")
                    }
                    pipelineSummary = pipeline.description
                    if myConfig.parsingConfig.runExplicit {
                        print(pipelineSummary)
                    }
                    //MARK: INGEST SENTS ::
                    currentStatus = "Ingesting sentences"
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
                        throw PipelineError.noSentencesLoaded
                    }
                    //MARK: run resentenciser on request
                    if ![InputFileType.txt, InputFileType.manual].contains(myConfig.inputConfig.inputFileType) && myConfig.parsingConfig.runResentenciser{
                        currentStatus = "Resentencizing"
                        myConfig.inputData.resentencizerOutputStrings = try desentenciseAndResentencise(
                            sentsToDiscard: allSentences,
                            myConfig: myConfig
                        )
                        myConfig.parsingConfig.runRetokeniser = true
                    }
                    
                    //MARK: run retokeniser if required/requested
                    if myConfig.inputConfig.inputFileType != .txt && myConfig.parsingConfig.runRetokeniser && [TokenizingMethod.nltokeniser, TokenizingMethod.trained].contains(myConfig.parsingConfig.tokenizingMethod) {
                        if myConfig.parsingConfig.runExplicit {
                            currentStatus = "retokenizing"
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
                        currentStatus = "getting NL Tags"
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
                        if myConfig.parsingConfig.runExplicit {
                            print("processing line 232")
                        }
                        currentStatus = "Ready to tag"
                        let sentResult = pipeline.runOnSentence(sentence, myConfig: myConfig)
                        switch sentResult.resultType {
                        case .success:
                            myConfig.outputData.outSents.append(
                                postprocessSentence(sentence: sentence, parsedTokens: sentResult.decoded , myConfig: myConfig)
                            )
                        default:
                            myConfig.outputData.outErrors.append(
                            postprocessErrorSent(sentResult: sentResult))
                            print("error handled")
                        }
                        
                        if myConfig.parsingConfig.runExplicit {
                            print("awaitng mainactor line 237")
                        }
                        await MainActor.run {
                            myConfig.progressConfig.processedCount += 1
                            myConfig.progressConfig.appleProgress.completedUnitCount = Int64(myConfig.progressConfig.processedCount)
                        }
                    }

                    try dumpDetailsForRunExplicit(myConfig: myConfig, taggingInProgress: $taggingInProgress)
                    runOutput = makeTidyRunOutput(myConfig: myConfig)
                    
                    try await MainActor.run {
                        taggingInProgress.wrappedValue = false
                        currentStatus = "Done"
                        guard let runOutput else {
                            throw PipelineError.noRunOutput
                        }
                        topLevelOutputList.append(runOutput)
                        if myConfig.parsingConfig.runExplicit{
                            print("topLevelOutputList length == \(topLevelOutputList.count)")
                        }
                    }
                } catch {
                    switch error {
                    case let PipelineError as PipelineError:
                        myConfig.progressConfig.alertMessage = PipelineError.errorDescription
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

