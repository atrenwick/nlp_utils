//
//  BertPipelineSettingsTestView.swift
//  Tagger
//
//  Created by Adam on 20/10/2026.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct BertPipelineSettingsTestView: View {
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
                    
                    Picker("architecture", selection: $myConfig.parsingConfig.modelArchitecture){
                        ForEach(ModelArchitecture.allCases){modarch in
                            Text(modarch.displayName)
                        }
                    }.onChange(of: myConfig.parsingConfig.modelArchitecture)
                    {if myConfig.parsingConfig.modelArchitecture == .distilbert {
                        myConfig.parsingConfig.selectedLanguage = .FR
                        myConfig.parsingConfig.selectedTreebank = .frTB1
                        myConfig.inputConfig.inputFileType = .conll
                        
                    }}
                    
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
                        isPipelineReady: isBPipelineReady,
                        missingReqsMessage: missingRequirementsMessage
                    )
                    PipelineProgressView(myConfig: $myConfig)
                    Button(
                        action:{
                            runTagging(
                                inputFileType: myConfig.inputConfig.inputFileType,
                                maxPipelineStep: myConfig.parsingConfig.maxPipelineStep,
                                taggingInProgress: $taggingInProgress,
                                isFirstRun: $isFirstRun
                            ) // close runTagging bracket
                        } // close action brace
                    ) // close button bracket
                    {
                        TaggingProgressButtonView(taggingInProgress: taggingInProgress, isPipelineReady: isBPipelineReady)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())
                    .controlSize(.large)
                    .disabled(taggingInProgress || !isBPipelineReady)
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
        // clear outputstruct data here AND onChange(of : inputfile
        if !isFirstRun.wrappedValue {
            myConfig.runResetters()
        } else {
            isFirstRun.wrappedValue = false
        }
        myConfig.parsingConfig.runExplicit = true
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
                
                let pipeline = try BERTlikePipeline(myConfig: myConfig)
                print(BERTlikePipeline.Type.self)
                var allSentences: [HashableSentence] = []
                
                //MARK: INGEST SENTS ::
                // deactivated as for txt, uses pipeline to tok, so dev with conll only
                //                allSentences = try ingestSentEncapsulator(
//                    myConfig: myConfig,
//                    pipeline: pipeline
//                )

                // resentencise internally in this function if set
                allSentences = try conllFileToHashableSentForPipeline(
                    inputURL: myConfig.inputConfig.selectedInputFile
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
//                if ![InputFileType.txt, InputFileType.manual].contains(myConfig.inputConfig.inputFileType) && myConfig.parsingConfig.runResentenciser{
//                    myConfig.inputData.resentencizerOutputStrings = try desentenciseAndResentencise(
//                        sentsToDiscard: allSentences,
//                        myConfig: myConfig
//                    )
//                    myConfig.parsingConfig.runRetokeniser = true
//                }
                
//                //MARK: run retokeniser if required/requested
//                if myConfig.inputConfig.inputFileType != .txt && myConfig.parsingConfig.runRetokeniser && [TokenizingMethod.nltokeniser, TokenizingMethod.trained].contains(myConfig.parsingConfig.tokenizingMethod) {
//                    if myConfig.parsingConfig.runExplicit {
//                        print("Retokenising")
//                    }
//                    allSentences = try retokenisationEncapsulator(
//                        myConfig: myConfig,
//                        pipeline: pipeline,
//                        taggingInProgress: taggingInProgress
//                    )
//                }
//                
//                // optional chunk to test build-in NL parsing, send POS, lemmas to cols 8,9
//                if myConfig.parsingConfig.runExplicit{
//                    var nlInputTexts: [String] = []
//                    for sent in allSentences{
//                        nlInputTexts.append(sent.tokens.joined(separator: " "))
//                    }
//                    for chunk in nlInputTexts{
//                        let _ = getNLTags(text: chunk)
//                    }
//                }
                
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
                    print("processing line 232")
                    let parsedTokens = try pipeline.runOnSentence(sentence, myConfig: myConfig)
                    myConfig.outputData.outSents.append(
                        postprocessSentence(sentence: sentence, parsedTokens: parsedTokens, myConfig: myConfig)
                    )
                    print("awaitng mainactor line 237")
                    await MainActor.run {
                        myConfig.progressConfig.processedCount += 1
                        myConfig.progressConfig.appleProgress.completedUnitCount = Int64(myConfig.progressConfig.processedCount)
                    }
                }
                
                try dumpDetailsForRunExplicit(myConfig: myConfig, taggingInProgress: $taggingInProgress)
                runOutput = makeTidyRunOutput(myConfig: myConfig)
                
                try await MainActor.run {
                    taggingInProgress.wrappedValue = false
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
    // copies from pipelineSettingsViewExtension
    var missingRequirements: [String] {
        var missing: [String] = []
        
        // Rule 1: Check input file exists in sandbox
        if fileContainerModel.localSandboxFileURL == nil && myConfig.inputConfig.inputFileType != .manual{
            missing.append("Input File")
        }

        let ext = fileContainerModel.localSandboxFileURL?.pathExtension ?? "nil"
        if  myConfig.inputConfig.inputFileType.allowedReadExt.contains(ext) == false  && myConfig.inputConfig.inputFileType != .manual {
            missing.append("extension-InputType Mismatch")
        }
        
        if myConfig.inputConfig.inputFileType == .manual && builtSents.count == 0 {
            missing.append("No built sents found")
        }
        
        // Rule 2: Check custom output filename is typed
        if myConfig.exportConfig.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Output Filename")
        }
        
        // Rule 3: Check target folder (or destination setting)
        if myConfig.exportConfig.targetFolderURL == nil {
            missing.append("Export Directory")
        }
        
        return missing
    }

    // 2. Boolean check for the .disabled() modifier
    var isBPipelineReady: Bool {
        return missingRequirements.isEmpty
    }

    // 3. User-friendly warning message
    var missingRequirementsMessage: String {
        guard !missingRequirements.isEmpty else { return "" }
        
        if missingRequirements.count == 1 {
            return "Set: \(missingRequirements[0])"
        } else {
            // Lists items cleanly: "Missing required settings: Input File, Output Filename, Export Directory"
            return "Missing required settings: \(missingRequirements.joined(separator: ", "))"
        }
    }

    
    
}

#Preview {
    BertPipelineSettingsTestView()
}
