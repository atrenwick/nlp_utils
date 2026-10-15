//
//  PipelineSettingsView.swift
//  Tagger
//
//  Created by Adam on 08/09/2026.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct PipelineSettingsView: View {
    
    @AppStorage("runExplicitDefault") var runExplicitDefault: Bool = false
    
    //MARK: defaults via AppStorage
    //input file
    
    // import + parsing
    @AppStorage("detectLangDefault") var detectLangDefault: Bool = false
    @AppStorage("progressBarStyleDefault") var progressBarStyleDefault: ProgressBarStyle = .apple

    //export

    // input file
    @State var inputFileType: InputFileType = .conll
    @State var fileContainerModel = SourceFileContainerModel()
    @State var selectedInputFile: URL? = nil
    @State var myConfig: TaggerConfig = TaggerConfig()

    // import, parsing settings
    @State var detectLanguage: Bool = false

    @State var tempTokens: [TempToken] = []
    
    // export settings
    
    //progressbars::
    @State private var appleProgress = Progress(totalUnitCount: 1)
    @State private var progressBarStyle: ProgressBarStyle = .apple
    @State private var startTime: Date?
    @State private var processedCount = 0
    @State private var totalCount = 0
    @State private var hasStarted = false
    
    // reporting
    @State private var topLevelOutputList: [RunOutput] = []
    @State private var exportStatusMessage: String?
    @State var outputString: String = "not yet run"
    @State private var runOutput: RunOutput?
    @State private var alertMessage: String?
    
    //controlling visibility
    @State var taggingInProgress: Bool = false
    @State var showImporter: Bool = false
    @State private var isSelectingFolder = false
    @State var hasAppeared: Bool = false
    // sentences ::
    @State var builtSents: [BuiltSentHolder] = []
    @State var sentsToRetokenise: [String] = []
    
    // outtput data
    @State var exportContent: String = ""
    @State var runExplicit: Bool = true //true // hardcoded bool for testing verbosity, display of test elements
    
    var unreadCount: Int {
        topLevelOutputList.reduce(0) { $1.runMetas.unread ? $0 + 1 : $0 }
    }
    #if DEBUG
    let runfive = false //
    #endif

    //TODO: funct exists to make same, but not called :: consider where, if, to use it
    var safeHeaderAttribs: XmlHeaderAttribs {
        let xmlSafeXMLAuthor = myConfig.exportConfig.xmlAuthorName.xmlEscaped != "" ? myConfig.exportConfig.xmlAuthorName.xmlEscaped : "author_unknown"
        let xmlSafeXMLTitle = myConfig.exportConfig.xmlTitle.xmlEscaped != "" ? myConfig.exportConfig.xmlTitle.xmlEscaped : "title"
        let xmlSafeLang = myConfig.parsingConfig.selectedLanguage.displayName.lowercased()
        let xmlsafeTreebank = myConfig.parsingConfig.selectedTreebank.short.xmlEscaped
        
        let formatter = DateFormatter()
        formatter.dateFormat = "y-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateString = formatter.string(from:Date())
        let xmlsafeDate = dateString.xmlEscaped
        
        let xmlsafeSourceFile = fileContainerModel.localSandboxFileURL?.path().xmlEscaped ?? "unk"
        let runID = UUID().uuidString
        
        let maxPipelineStep = myConfig.parsingConfig.maxPipelineStep.title.xmlEscaped
        let runRetokeniser = String(myConfig.parsingConfig.runRetokeniser).xmlEscaped
        let tokenizingMethod = myConfig.parsingConfig.tokenizingMethod.rawValue.xmlEscaped
        let sentencizingMethod = myConfig.parsingConfig.sentencizingMethod.rawValue.xmlEscaped
        
        let outputStruct = XmlHeaderAttribs(
            xmlTitle: xmlSafeXMLTitle,
            xmlAuthorName: xmlSafeXMLAuthor,
            lang: xmlSafeLang,
            treebank: xmlsafeTreebank,
            taggingDate: xmlsafeDate,
            sourceFile: xmlsafeSourceFile,
            runID: runID,
            maxPipelineStep: maxPipelineStep,
            runRetokeniser: runRetokeniser,
            tokenizingMethod: tokenizingMethod,
            sentencizingMethod: sentencizingMethod,
        )
        return outputStruct
    }
    
    var body: some View {
        
        NavigationStack{
            Form {
                Picker("Inputtype", selection: $myConfig.inputConfig.inputFileType){
                    ForEach(InputFileType.allCases){fType in
                        Text(fType.rawValue)}
                }
                .onChange(of: inputFileType) { _, newFileType in
                    if newFileType != .manual && detectLanguage {
                        if let detectedLang = detectLangInFilename(
                            inputURL: fileContainerModel.localSandboxFileURL) {
                            myConfig.parsingConfig.selectedLanguage = detectedLang
                        }
                    }
                    if newFileType == .manual {
                        myConfig.parsingConfig.runRetokeniser = false
                    }
                    if newFileType == .txt {
                        myConfig.parsingConfig.runRetokeniser = true
                    }
                }
                .accessibilityIdentifier("InputTypePicker")

                // First Picker
                Section("Parameters"){
                    if inputFileType == .manual {
                        Section {
                            NavigationLink("Manual entry…"){
                                ManualTokenisationView(
                                    myConfig: $myConfig,
                                    builtSents: $builtSents,
                                    tempTokens: $tempTokens
                                )
                            }
                        }
                    } else {
                        Section{
                            ImportFileViewSection(fileContainerModel: fileContainerModel, myConfig: $myConfig )
                        }
                    }
                    Toggle(isOn: $detectLanguage) {
                        Text("Autodetect Language")
                    }.onChange(of: detectLanguage){_, newValue in
                        if newValue == true {
                            if let detectedLang = detectLangInFilename(inputURL:fileContainerModel.localSandboxFileURL){
                                myConfig.parsingConfig.selectedLanguage = detectedLang
                            }
                        }
                    }
                    .accessibilityIdentifier("DetectLanguageToggle")

                    Picker("Language", selection: $myConfig.parsingConfig.selectedLanguage) {
                        ForEach(Language.allCases) { lang in
                            Text(lang.rawValue)
                        }
                    }
                    .onChange(of: fileContainerModel.localSandboxFileURL){
                        if detectLanguage {
                            if let detectedLang = detectLangInFilename(inputURL:fileContainerModel.localSandboxFileURL){
                                myConfig.parsingConfig.selectedLanguage = detectedLang
                            }
                        }
                    }
                    .onChange(of: myConfig.parsingConfig.selectedLanguage) { _, newLang in
                        if let first = newLang.availableTBs.first {
                            myConfig.parsingConfig.selectedTreebank = first
                        }
                    }
                    .accessibilityIdentifier("LanguagePicker")

                    Picker("Treebank", selection: $myConfig.parsingConfig.selectedTreebank) {
                        ForEach(myConfig.parsingConfig.selectedLanguage.availableTBs) { tb in
                            Text(tb.short).tag(tb)
                        }
                    }
                    .onChange(of: myConfig.parsingConfig.selectedLanguage) { _, newLang in
                        myConfig.parsingConfig.selectedTreebank = newLang.defaultTB
                    }
                    .accessibilityIdentifier("TreebankPicker")

                    NavigationLink("Select processor steps"){
                        ProcessorStepConfigViewSection(myConfig: $myConfig)
                    }.accessibilityIdentifier("ProcessorStepLink")
                }
               
                ExportConfigViewSection(myConfig: $myConfig)

                if runExplicit {
                    HStack{
                        Button {
                            outputString = testInstantiatePipeline(
                                languageCode: myConfig.parsingConfig.selectedLanguage.rawValue,
                                treebank: myConfig.parsingConfig.selectedTreebank.short
                            )
                        } label: {
                            Text("Test load")
                        }
                        .tint(.orange)
                        .buttonStyle(.borderedProminent)
                        
                        Button {
                            outputString = "reset"
                        } label: {
                            Text("reset")
                        }
                        .tint(.blue)
                        .buttonStyle(.borderedProminent)
                        
                        Text("Use \(myConfig.parsingConfig.selectedLanguage.displayName) \(myConfig.parsingConfig.selectedTreebank.short)")
                        Text(outputString)
                    }
                }
                // MARK: the Go button
                Section {
                    if !isPipelineReady {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(missingRequirementsMessage)
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if hasStarted {
                        PipelineProgressView(
                            style: progressBarStyle,
                            processed: processedCount,
                            total: totalCount,
                            startTime: startTime,
                            appleProgress: appleProgress
                        )
                    }
                    Button(
                        action:{
                            runTagging(
                                inputFileType: inputFileType,
                                maxPipelineStep: myConfig.parsingConfig.maxPipelineStep,
                                taggingInProgress: $taggingInProgress
                            ) // close runTagging bracket
                        } // close action brace
                    ) // close button bracket
                    {
                        ZStack {
                            HStack {
                                Image(systemName: taggingInProgress ? "progress.indicator" : "play.fill")
                                    .symbolEffect(.rotate, options: .repeating, isActive: taggingInProgress)
                                Text(taggingInProgress ? "Running" : "Run")
                                    .fontWeight(.semibold)
                                //                            .opacity(taggingInProgress ? 1 : 1)
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())
                    .controlSize(.large)
                    .disabled(taggingInProgress || !isPipelineReady)
                    .padding()
                }//close Go button section
                .alert(
                    " Error",
                    isPresented: Binding(
                        get: {alertMessage != nil},
                        set: {if !$0 {alertMessage = nil}}
                    )
                )
                {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(alertMessage ?? "")
                }
            }
            // default values on appear
            .onAppear {
                runExplicit = runExplicitDefault
                if hasAppeared == false {
                    detectLanguage = detectLangDefault
                    progressBarStyle = progressBarStyleDefault
                    hasAppeared = true
                }
            }
            .accessibilityIdentifier("RunParsingButton")

            // MARK: toolbar :
            .toolbar{
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RunOutputView(
                            myConfig: $myConfig,
                            runs: $topLevelOutputList,
                            safeHeaderAttribs: safeHeaderAttribs,
                            builtSents: $builtSents,
                            tempTokens: $tempTokens,
                        )
                    } label: {
                        Image(systemName: "book.pages.fill")
                            .overlay(alignment: .topTrailing) {
                                if unreadCount > 0 {
                                    Text(String(unreadCount))
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(Circle().fill(.red))
                                        .offset(x: 8, y: -8)
                                }
                            }
                    }
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
            startTime = nil
            hasStarted = true
            processedCount = 0
            totalCount = 0
            var resentencizerOutputStrings: [String] = []
            var outSents: [Sentence] = []

            let saveInputMetas = SaveInputMetas(
                lang: myConfig.parsingConfig.selectedLanguage,
                displayName: inputFileType == .manual ? "Manual Entry" : fileContainerModel.selectedFileName,
                inputURL: fileContainerModel.localSandboxFileURL,
                saveName: myConfig.exportConfig.fileName,
                targetFolderURL: myConfig.exportConfig.targetFolderURL,
                exportFormat: myConfig.exportConfig.selectedExportFormat,
                treebank: myConfig.parsingConfig.selectedTreebank,
                safeHeaderAttribs: safeHeaderAttribs,
                includeConllSentText: myConfig.exportConfig.includeConllSentText
            )

            // MARK: tagging :
            Task {
                do {
                    // get pipeline object
                    let pipeline = try UDPipeline(
                        languageCode: saveInputMetas.lang.rawValue,
                        treebank: saveInputMetas.treebank.short)
                    var allSentences: [HashableSentence] = []
                    
                    //MARK: INGEST SENTS ::
                    allSentences = try ingestSentEncapsulator(
                        inputFileType: inputFileType,
                        saveInputMetas: saveInputMetas,
                        builtSents: builtSents,
                        sentencizingMethod: myConfig.parsingConfig.sentencizingMethod,
                        tokenizingMethod: myConfig.parsingConfig.tokenizingMethod,
                        pipeline: pipeline,
                        runExplicit: runExplicit
                    )
                    //MARK: check we have sents
                    guard !allSentences.isEmpty else {
                        taggingInProgress.wrappedValue = false
                        throw ParseProcessingError.noSentencesLoaded
                    }
                    //MARK: run resentenciser on request
                    if ![InputFileType.txt, InputFileType.manual].contains(inputFileType) && myConfig.parsingConfig.runResentenciser{
                        resentencizerOutputStrings = try desentenciseAndResentencise(
                            sentsToDiscard: allSentences,
                            lang: myConfig.parsingConfig.selectedLanguage,
                            sentencizingMethod: myConfig.parsingConfig.sentencizingMethod,
                            runExplicit: runExplicit
                        )
                        myConfig.parsingConfig.runRetokeniser = true
                    }
                    
                    //MARK: run retokeniser if required/requested
                    if myConfig.inputConfig.inputFileType != .txt && myConfig.parsingConfig.runRetokeniser && [TokenizingMethod.nltokeniser, TokenizingMethod.trained].contains(myConfig.parsingConfig.tokenizingMethod) {
                        if runExplicit {
                            print("Retokenising")
                        }
                        allSentences = try retokenisationEncapsulator(
                            allSentences: allSentences,
                            tokenizingMethod: myConfig.parsingConfig.tokenizingMethod,
                            lang: myConfig.parsingConfig.selectedLanguage,
                            pipeline: pipeline,
                            runResentenciser: myConfig.parsingConfig.runResentenciser,
                            resentencizerOutputStrings: resentencizerOutputStrings,
                            taggingInProgress: taggingInProgress,
                            runExplicit: runExplicit
                        )
                    }

                    // optional chunk to test build-in NL parsing, send POS, lemmas to cols 8,9
                    if runExplicit{
                        var nlInputTexts: [String] = []
                        for sent in allSentences{
                            nlInputTexts.append(sent.tokens.joined(separator: " "))
                        }
                        for chunk in nlInputTexts{
                            let _ = getNLTags(text: chunk)
                        }
                    }

                    await MainActor.run {
                        totalCount = allSentences.count
                        appleProgress = Progress(totalUnitCount: Int64(max(allSentences.count, 1)))
                        startTime = Date()
                    }

                    // MARK: Step 2: pass prepared data to parsing pipeline
#if DEBUG
                    if runfive {
                        allSentences = allSentences.count > 5 ? Array(allSentences.prefix(5)) : allSentences}
#endif
                    for sentence in allSentences {
                        let parsedTokens = try pipeline.runOnSentence(sentence, level: maxPipelineStep.rawValue)
                        outSents.append(
                            postprocessSentence(sentence: sentence, parsedTokens: parsedTokens, runExplicit: runExplicit, maxPipelineStep: maxPipelineStep)
                        )
                        
                        await MainActor.run {
                            processedCount += 1
                            appleProgress.completedUnitCount = Int64(processedCount)
                        }
                    }
#if DEBUG
                    dumpDetailsForRunExplicit(runExplicit: runExplicit, outSents: outSents, targetFolderURL: myConfig.exportConfig.targetFolderURL, fileName: myConfig.exportConfig.fileName)
#endif
                    runOutput = makeTidyRunOutput(
                        outSents: outSents,
                        saveInputMetas: saveInputMetas,
                        safeHeaderAttribs: safeHeaderAttribs
                    )
                    
                    if runExplicit {
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
                        if runExplicit{
                            print("topLevelOutputList length == \(topLevelOutputList.count)")
                        }
                    }
                } catch {
                    switch error {
                    case let parseProcessingError as ParseProcessingError:
                        alertMessage = parseProcessingError.errorDescription
                    case let nsError as NSError where nsError.domain == XMLParser.errorDomain:
                        alertMessage = "XML Parsing error : No valid XML to parse"
                    default:
                        alertMessage = error.localizedDescription
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

