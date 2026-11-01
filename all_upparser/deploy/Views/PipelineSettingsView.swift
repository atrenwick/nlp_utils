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
    @State internal var loadedCount = 0
    @State internal var loadStatus = ""
    @State internal var topLevelOutputList: [RunOutput] = []
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
    
    var unreadCount: Int {
        topLevelOutputList.reduce(0) { $1.runMetas.unread ? $0 + 1 : $0 }
    }
#if DEBUG
    let runfive = false //
#endif
    
    var body: some View {
        NavigationStack{
            Form {
                InputTypeExtractedView(myConfig: $myConfig, fileContainerModel: $fileContainerModel)
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
                    
                    Toggle(isOn: $myConfig.inputConfig.detectLanguage) {
                        Text("Autodetect Language")
                    }.onChange(of: myConfig.inputConfig.detectLanguage){_, newValue in
                        if newValue == true {
                            print("case1")
                            if let detectedLang = FileIngestionWorkflow.detectLangInFilename(inputURL:fileContainerModel.localSandboxFileURL){
                                print("case2")
                                myConfig.parsingConfig.selectedLanguage = detectedLang
                            } else {print("case 3")}
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
                    BigGoButtonReadinessExtractedView(
                        isPipelineReady: isPipelineReady,
                        missingReqsMessage: missingReqsMessage
                    )
                    if isLoading {
                        VStack {
                            ProgressView(value: Double(loadedCount), total: Double(loadTotal))
                            Text(loadStatus)
                        }
                    }
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
                        }
                    )
                    {
                        TaggingProgressButtonExtractedView(taggingInProgress: taggingInProgress, isPipelineReady: isPipelineReady, pipelineSummary: pipelineSummary)
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
            // default values on appear
            .accessibilityIdentifier("RunParsingButton")
            
            // MARK: toolbar :
            .toolbar{
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarLinkToOutputExtractedView(
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
}

#Preview {
    PipelineSettingsView()
}



extension PipelineSettingsView {
    //MARK:  calculated properties
    var loadTotal: Int {
        if myConfig.parsingConfig.modelArchitecture == .distilbert {
            return 4
        } else {
            return 10
        }
    }

    // 1. Array of missing configuration items
    var missingReqs: [String] {
        var missing: [String] = []
        
        // Rule 1: Check input file exists in sandbox
        if fileContainerModel.localSandboxFileURL == nil && myConfig.inputConfig.inputFileType != .manual{
            missing.append("Input File")
        }
        
        let ext = fileContainerModel.localSandboxFileURL?.pathExtension ?? "nil"
        if  myConfig.inputConfig.inputFileType.allowedReadExt.contains(ext) == false  && myConfig.inputConfig.inputFileType != .manual {
            missing.append("extension-InputType Mismatch")
        }
        
        if myConfig.inputConfig.inputFileType == .manual && myConfig.inputData.builtSents.count == 0 {
            missing.append("No built sents found")
        }
        
        // Rule 2: Check custom output filename is typed
        if myConfig.exportConfig.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Output Filename")
        }
        
        // Rule 3: Check target folder (or destination setting)
        if myConfig.exportConfig.targetFolderURL == nil { // and in sandbox || has auth.
            missing.append("Export Directory")
        }
        
        return missing
    }
    
    // 2. Boolean check for the .disabled() modifier
    var isPipelineReady: Bool {
        return missingReqs.isEmpty
    }
    
    // 3. User-friendly warning message
    var missingReqsMessage: String {
        guard !missingReqs.isEmpty else { return "" }
        
        if missingReqs.count == 1 {
            return "Set: \(missingReqs[0])"
        } else {
            // Lists items cleanly: "Missing required settings: Input File, Output Filename, Export Directory"
            return "Missing required settings: \(missingReqs.joined(separator: ", "))"
        }
    }
    
    //MARK: instance methods
    func processSentsFromPipeline(sentResult: OnSentResult, myConfig: Binding<TaggerConfig>)   {
        
        switch sentResult.resultType {
        case .success:
            myConfig.wrappedValue.outputData.outSents.append(
                PostPipelineWorkflow.postprocessSentence(sentence: sentResult.sentence, parsedTokens: sentResult.decoded, myConfig: myConfig.wrappedValue)
            )
        default:
            myConfig.wrappedValue.outputData.outErrors.append(PostPipelineWorkflow.postprocessErrorSent(sentResult: sentResult))
            print("error handled")
        }
        if myConfig.wrappedValue.parsingConfig.runExplicit { print("awaitng mainactor line 237") }
    }
    
    func callPipelineLoader(myConfig: TaggerConfig) async throws -> PipelineHelper{
        let pipeline: PipelineHelper
        var currentStatus: String = ""
        isLoading = true
        do {
            switch myConfig.parsingConfig.modelArchitecture {
            case .camembert, .roberta:
                let loader = CamemBERTlikePipelineLoader()
                pipeline = try await loader.loadCamemBERTlikePipeline(myConfig: myConfig) {step, message in
                    loadedCount = step
                    loadStatus = message
                }
                if myConfig.parsingConfig.runExplicit { print("camembert pipeline called") }
            case .distilbert:
                let loader = DistilBERTlikePipelineLoader()
                pipeline = try await loader.loadDistilBERTlikePipe(myConfig: myConfig) {step, message in
                    loadedCount = step
                    loadStatus = message
                }
                if myConfig.parsingConfig.runExplicit { print("bert pipeline called") }
            case .cnnBiLSTM:
                let loader = CNNBiLSTMPipelineLoader()
                pipeline = try await loader.loadCNNBiLSTMpipe(myConfig: myConfig) {step, message in
                    loadedCount = step
                    loadStatus = message
                }
                currentStatus = "loaded cnnBiLSTM"
                if myConfig.parsingConfig.runExplicit { print("loaded cnnBiLSTM") }
            }
        } catch {
            if myConfig.parsingConfig.runExplicit { print("Failed to load pipeline: \(error)")}
            currentStatus = "Error loading pipeline."
            throw PipelineError.ConfigurationError.notReadyToSendToRunner
        }
        
        if myConfig.parsingConfig.runExplicit { print(currentStatus) }
        isLoading = false
        return pipeline
    }

    func runTagging(
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
        let theseHeaderAttribs = XMLMakingWorkflow.makeSafeHeaderAttribs(myConfig: myConfig, fileContainerModel: fileContainerModel)
        if myConfig.parsingConfig.runExplicit { print("Build header attribs: \(theseHeaderAttribs)") }
        myConfig.outputData.safeHeaderAttribs = theseHeaderAttribs
        
    
        // MARK: tagging :
        Task {
            do {
                var allSentences: [HashableSentence] = []
                var pipeline: PipelineHelper
                do {
                    currentStatus = "Loading pipeline"
                    pipeline = try await callPipelineLoader(myConfig: myConfig)
                    myConfig.parsingConfig.maxWords = pipeline.maxWords
                    myConfig.outputData.safeHeaderAttribs.maxWords = String(pipeline.maxWords)
                    //MARK: set pipeline maxwords, seqlen
                    if myConfig.parsingConfig.runExplicit { print("Pipelinemax_words = \(pipeline.maxWords) @ 228") }
                    if let pipeline = pipeline as? SubtokenAwarePipelineHelper {
                        myConfig.outputData.safeHeaderAttribs.maxSeqLen = String(pipeline.seqLen)
                        myConfig.parsingConfig.maxSeqLen = pipeline.seqLen
                        if myConfig.parsingConfig.runExplicit { print("maxSeqLen = \(pipeline.seqLen) @ 232")}
                    }
                } catch {
                    if myConfig.parsingConfig.runExplicit { print("Failed to load pipeline: \(error)") }
                    currentStatus = "Error loading pipeline."
                    throw PipelineError.ConfigurationError.notReadyToSendToRunner
                }
                if myConfig.parsingConfig.runExplicit { print(currentStatus) }
                
                //MARK: INGEST SENTS ::
                allSentences = try SentencizationWorkflow.ingestSentences(currentStatus: currentStatus, myConfig: myConfig, pipeline: pipeline)
                guard !allSentences.isEmpty else {
                    taggingInProgress.wrappedValue = false
                    throw PipelineError.IngestionError.noSentencesLoaded
                }
                
                //MARK: run resentenciser on request
                if ![InputFileType.txt, InputFileType.manual].contains(myConfig.inputConfig.inputFileType) && myConfig.parsingConfig.runResentenciser{
                    currentStatus = "Resentencizing"
                    myConfig.inputData.resentencizerOutputStrings = try SentencizationWorkflow.desentenciseAndResentencise(
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
                    allSentences = try SentencizationWorkflow.retokenisationEncapsulator(
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
                    if myConfig.parsingConfig.runExplicit { print("processing line 232") }
                    currentStatus = "Ready to tag"
                    var sentResult: OnSentResult?
                    if let bertDerivedPipe = pipeline as? BERTderivedPipelineHelper{
                        sentResult = try bertDerivedPipe.runOnSentence(sentence, myConfig: myConfig)
                    } else {
                        if let cnnPipeline = pipeline as? CNNBiLSTMPipeline {
                            sentResult =  cnnPipeline.runOnSentence(sentence, myConfig: myConfig)
                        }
                    }
                    if let success =  sentResult {
                        processSentsFromPipeline(sentResult: success, myConfig: $myConfig )
                    }
                    
                                             
                    await MainActor.run {
                        myConfig.progressConfig.processedCount += 1
                        myConfig.progressConfig.appleProgress.completedUnitCount = Int64(myConfig.progressConfig.processedCount)
                    }
                }
//MARK: print
                try PrintWorkflow.dumpDetailsForRunExplicit(myConfig: myConfig, taggingInProgress: $taggingInProgress)
                runOutput = PostPipelineWorkflow.makeTidyRunOutput(myConfig: myConfig)
                
                try await MainActor.run {
                    taggingInProgress.wrappedValue = false
                    currentStatus = "Done"
                    guard let runOutput else { throw PipelineError.ProcessingError.noRunOutput }
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

//let modelURL = Bundle.main.url(
//    forResource: "my_model",
//    withExtension: "mlpackage",
//    subdirectory: "ExternalModels/cnn_bi_lstm" // Reflects the nested path inside the blue folder
//)

