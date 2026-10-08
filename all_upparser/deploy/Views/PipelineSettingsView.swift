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
    @AppStorage("inputFileTypeDefault") var inputFileTypeDefault: InputFileType = .txt
    
    // import + parsing
    @AppStorage("detectLangDefault") var detectLangDefault: Bool = false
    @AppStorage("selectedLanguageDefault") var selectedLanguageDefault: Language = .FR
    @AppStorage("selectedTreebankDefault") var selectedTreebankDefault: Language.Treebank = .frTB3
    @AppStorage("tokenizingMethodDefault") var tokenizingMethodDefault: TokenizingMethod = .nltokeniser
    @AppStorage("sentencizingMethodDefault")  var sentencizingMethodDefault: SentencizingMethod = .nlSentencizer
    @AppStorage("maxPipelineStepDefault")  var maxPipelineStepDefault: PipelineStep = .step5
    
    //export
    @AppStorage("selectedExportFormatDefault") var selectedExportFormatDefault: ExportFormat = .xml
    @AppStorage("xmlAuthorDefault") var xmlAuthorDefault: String = "XML Author"
    @AppStorage("xmlTitleDefault") var xmlTitleDefault: String = "XML Title"
    @AppStorage("fileNameDefault") var fileNameDefault: String = "fileName"

    @AppStorage("includeConllSentIdLineDefault") var includeConllSentIdLineDefault: Bool = true
    @AppStorage("includeConllSentTextDefault") var includeConllSentTextDefault: Bool = true

    
    

    // input file
    @State var inputFileType: InputFileType = .conll
    @State var fileContainerModel = SourceFileContainerModel()
    @State var selectedInputFile: URL? = nil
    
    
    // import, parsing settings
    @State var detectLanguage: Bool = false
    @State var selectedLanguage: Language = .FR
    @State var selectedTreebank: Language.Treebank = .frTB1
    
    @State var maxPipelineStep: PipelineStep = .step5
    @State var runRetokeniser: Bool = false
    @State var tokenizingMethod: TokenizingMethod = .nltokeniser
    @State var sentencizingMethod: SentencizingMethod = .nlSentencizer
    
    // export settings
    @State var fileName: String = "Filename"
    @State var targetFolderURL: URL? = nil
    @State var selectedExportFormat: ExportFormat = .xml
    @State var xmlAuthorName: String = "XML Author"
    @State var xmlTitle: String = "XML Title"
    
    @State var includeConllSentIdLine: Bool = true
    @State var includeConllSentText: Bool = true

    
    //progressbars::
    @State private var appleProgress = Progress(totalUnitCount: 1)
    @State private var progressBarStyle: ProgressBarStyle = .apple
    @State private var startTime: Date?
    @State private var processedCount = 0
    @State private var totalCount = 0
    @State private var hasStarted = false
    
    // reporting
    @State private var errorMessage: String?
    @State private var topLevelOutputList: [RunOutput] = []
    @State private var exportStatusMessage: String?
    @State var outputString: String = "not yet run"
    @State private var runOutput: RunOutput?
    
    //controlling visibility
    @State var taggingInProgress: Bool = false
    @State var showImporter: Bool = false
    @State private var isSelectingFolder = false
    @State var hasAppeared: Bool = false
    // sentences ::
    @State var builtSents: [BuiltSentHolder] = []
    @State var sentsToRetokenise: [String] = []
    @State private var testSentences = ["Paris est la capitale de la France.", "La capitale de l'Allemagne est Berlin, mais avant, c'était Bonn mais on trouvait que c'était pas bon.", "Paris est une grande ville française"]
    @State private var newSentence: String = ""
    
    // outtput data
    @State var exportContent: String = ""
    
    @State private var alertMessage: String?
    
    @State var runExplicit: Bool = true //true // hardcoded bool for testing verbosity, display of test elements
    
    var unreadCount: Int {
        topLevelOutputList.reduce(0) { $1.runMetas.unread ? $0 + 1 : $0 }
    }
    
    //TODO: funct exists to make same, but not called :: consider where, if, to use it
    var safeHeaderAttribs: XmlHeaderAttribs {
        let xmlSafeXMLAuthor = xmlAuthorName.xmlEscaped != "" ? xmlAuthorName.xmlEscaped : "author_unknown"
        let xmlSafeXMLTitle = xmlTitle.xmlEscaped != "" ? xmlTitle.xmlEscaped : "title"
        let xmlSafeLang = selectedLanguage.displayName.lowercased()
        let xmlsafeTreebank = selectedTreebank.short.xmlEscaped
        
        let formatter = DateFormatter()
        formatter.dateFormat = "y-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateString = formatter.string(from:Date())
        let xmlsafeDate = dateString.xmlEscaped
        
        let xmlsafeSourceFile = fileContainerModel.localSandboxFileURL?.path().xmlEscaped ?? "unk"
        let runID = UUID().uuidString
        
        let maxPipelineStep = maxPipelineStep.title.xmlEscaped
        let runRetokeniser = String(runRetokeniser).xmlEscaped
        let tokenizingMethod = tokenizingMethod.rawValue.xmlEscaped
        let sentencizingMethod = sentencizingMethod.rawValue.xmlEscaped
        
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
                Picker("Inputtype", selection: $inputFileType){
                    ForEach(InputFileType.allCases){fType in
                        Text(fType.rawValue)}
                }.onChange(of: inputFileType) { _, newFileType in
                    if newFileType != .manual && detectLanguage {
                        if let detectedLang = detectLangInFilename(
                            inputURL: fileContainerModel.localSandboxFileURL) {
                            selectedLanguage = detectedLang
                        }
                    }
                    if newFileType == .manual {
                        runRetokeniser = false
                    }
                    if newFileType == .txt {
                        runRetokeniser = true
                    }
                }
                .accessibilityIdentifier("InputTypePicker")

                // First Picker
                Section("Parameters"){
                    if inputFileType != .manual {
                        Section{
                            ImportFileViewSection(fileContainerModel: fileContainerModel, inputFileType: inputFileType )
                        }
                    } else {
                        Section {
                            NavigationLink("Manual entry…"){
                                ManualTokenisationView(selectedLanguage: $selectedLanguage,builtSents: $builtSents)
                            }
                        }
                    }
                    Toggle(isOn: $detectLanguage) {
                        Text("Autodetect Language")
                    }.onChange(of: detectLanguage){_, newValue in
                        if newValue == true {
                            if let detectedLang = detectLangInFilename(inputURL:fileContainerModel.localSandboxFileURL){
                                selectedLanguage = detectedLang
                            }
                        }
                    }
                    .accessibilityIdentifier("DetectLanguageToggle")

                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(Language.allCases) { lang in
                            Text(lang.rawValue)
                        }
                    }
                    .onChange(of: fileContainerModel.localSandboxFileURL){
                        if detectLanguage {
                            if let detectedLang = detectLangInFilename(inputURL:fileContainerModel.localSandboxFileURL){
                                selectedLanguage = detectedLang
                            }
                        }
                    }
                    .onChange(of: selectedLanguage) { _, newLang in
                        if let first = newLang.availableTBs.first {
                            selectedTreebank = first
                        }
                    }
                    .accessibilityIdentifier("LanguagePicker")

                    Picker("Treebank", selection: $selectedTreebank) {
                        ForEach(selectedLanguage.availableTBs) { tb in
                            Text(tb.short).tag(tb)
                        }
                    }
                    .onChange(of: selectedLanguage) { _, newLang in
                        selectedTreebank = newLang.defaultTB
                    }
                    .accessibilityIdentifier("TreebankPicker")

                    NavigationLink("Select processor steps"){
                        ProcessorStepConfigViewSection(
                            maxActiveStep: $maxPipelineStep,
                            inputFileType: $inputFileType,
                            runRetokeniser: $runRetokeniser,
                            tokenizingMethod: $tokenizingMethod
                        )
                    }.accessibilityIdentifier("ProcessorStepLink")
                }//end section
               
                ExportConfigViewSection(
                    fileName: $fileName,
                    targetFolderURL: $targetFolderURL,
                    selectedExportFormat: $selectedExportFormat,
                    xmlAuthorName: $xmlAuthorName,
                    xmlTitle: $xmlTitle,
                    includeConllSentIdLine: $includeConllSentIdLine,
                    includeConllSentText: $includeConllSentText
                )
                

                
                if runExplicit {
                    HStack{
                        Button {
                            outputString = testInstantiatePipeline(
                                languageCode: selectedLanguage.rawValue,
                                treebank: selectedTreebank.short
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
                        
                        Text("Use \(selectedLanguage.displayName) \(selectedTreebank.short)")
                        Text(outputString)
                    }
                }
                Section { // Go button
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
                                maxPipelineStep: maxPipelineStep,
                                taggingInProgress: $taggingInProgress
                            )
                        })
                    {
                        ZStack {
                            HStack {
                                Image(systemName: "play.fill")
                                Text(taggingInProgress ? "Running" : "Run")
                                    .fontWeight(.semibold)
                            }
                            .opacity(taggingInProgress ? 0.5 : 1)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(taggingInProgress || !isPipelineReady)
//                    .animation(.easeInOut(duration: 0.001), value: isPipelineReady)
                    .padding()
                }
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
                    inputFileType = inputFileTypeDefault
                    selectedLanguage = selectedLanguageDefault
                    detectLanguage = detectLangDefault
                    selectedTreebank = selectedTreebankDefault
                    tokenizingMethod = tokenizingMethodDefault
                    sentencizingMethod = sentencizingMethodDefault
                    selectedExportFormat = selectedExportFormatDefault
                    xmlAuthorName = xmlAuthorDefault
                    xmlTitle = xmlTitleDefault
                    includeConllSentIdLine = includeConllSentTextDefault
                    includeConllSentText = includeConllSentTextDefault
                    fileName = fileNameDefault
                    maxPipelineStep = maxPipelineStepDefault
                    hasAppeared = true
                }
            }
            .accessibilityIdentifier("RunParsingButton")
            .toolbar{
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RunOutputView(
                            runs: $topLevelOutputList,
                            xmlTitle: $xmlTitle,
                            selectedLanguage: $selectedLanguage,
                            xmlAuthor: $xmlAuthorName,
                            targetFolderURL: $targetFolderURL,
                            fileName: $fileName,
                            selectedTreebank : $selectedTreebank,
                            builtSents: $builtSents,
                            inputFileType: $inputFileType,
                            safeHeaderAttribs: safeHeaderAttribs
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
            //MARK: parameters, initialisations for task
            taggingInProgress.wrappedValue = true
            
            let saveInputMetas = SaveInputMetas(
                lang: selectedLanguage,
                displayName: inputFileType == .manual ? "Manual Entry" : fileContainerModel.selectedFileName,
                inputURL: fileContainerModel.localSandboxFileURL,
                saveName: fileName,
                targetFolderURL: targetFolderURL,
                exportFormat: selectedExportFormat,
                treebank: selectedTreebank,
                safeHeaderAttribs: safeHeaderAttribs,
                includeConllSentText: includeConllSentText
            )
            errorMessage = nil
            startTime = nil
            hasStarted = true
            processedCount = 0
            totalCount = 0
            
            
            Task {
                // MARK: tagging :
                do {
                    // get pipeline object
                    let pipeline = try UDPipeline(
                        languageCode: saveInputMetas.lang.rawValue,
                        treebank: saveInputMetas.treebank.short)
                    var allSentences: [HashableSentence] = []
                    
                    //MARK: INGEST SENTS ::
                    
                    switch inputFileType {
                    case .conll:
                        allSentences = try conllFileToHashableSentForPipeline(
                            inputURL: saveInputMetas.inputURL
                        )
                    case .manual:
                        allSentences = builtSents.map {$0.hashableSent}
                        
                    case .xml:
                        allSentences = try xmlToHashableSentForPipeline(
                            inputURL: saveInputMetas.inputURL
                        )
                    case .xmlConll:
                        allSentences = try xmlConllFileToHashableSentForPipeline(
                            inputURL: saveInputMetas.inputURL
                        )
                    case .txt:
                        // this uses NaturalLanguage tagger as a sentenciser or custom ruleset (not yet written to sentencize blobs of text
                        allSentences = try textFileToHashableSents(
                            inputURL: saveInputMetas.inputURL,
                            sentencizingMethod: sentencizingMethod,
                            tokenizingMethod: tokenizingMethod,
                            lang: saveInputMetas.lang,
                            pipeline: pipeline
                        )
                        //                    let sentencesAsStrings = textFileToSentStrings(
                        //                        inputURL: saveInputMetas.inputURL,
                        //                        sentencizingMethod: sentencizingMethod,
                        //                        lang: selectedLanguage
                        //                    )
                        //                    switch tokenizingMethod{
                        //                    case .custom:
                        //                        print("using custom rules:: need to get Swift version of rules……")
                        //                    case .nltokeniser:
                        //                        allSentences = getTokenisedSentences(sents: sentencesAsStrings, lang: selectedLanguage)
                        //
                        //                        print("nltokeniser")
                        //                    case .trained:
                        //                        // retokenize everything with model
                        //                        // MARK: can change this IN to be testSentences
                        //                        for sentence in sentencesAsStrings {
                        //                            allSentences.append(contentsOf: try pipeline.tokenize(sentence))
                        //
                        //                    }
                        //                    }
                        print("Mode a: \(allSentences.count) sents ")
                        
                    }
                    guard !allSentences.isEmpty else {
                        taggingInProgress.wrappedValue = false
                        throw ParseProcessingError.noSentencesLoaded
                    }
                    
                    if inputFileType != .txt && runRetokeniser && [TokenizingMethod.nltokeniser, TokenizingMethod.trained].contains(tokenizingMethod)  {
                        print("Retokenising")
                        var sentencesAsStrings: [String] = []
                        for sent in allSentences{
                            sentencesAsStrings.append(sent.detokenised)
                        }
                        
                        let retokenisedSents = try stringSentsToHashableSents(tokenizingMethod: tokenizingMethod, sents: sentencesAsStrings, lang: saveInputMetas.lang, pipeline: pipeline)
                        guard !retokenisedSents.isEmpty else {
                            taggingInProgress.wrappedValue = false
                            throw ParseProcessingError.retokenisationError
                        }
                        allSentences = retokenisedSents
                    }
                    
                    // optional chunk to test build-in NL parsing, send POS, lemmas to cols 8,9
                    if runExplicit{
                        var nlInputTexts: [String] = []
                        for sent in allSentences{
                            nlInputTexts.append(sent.tokens.joined(separator: " "))
                        }
                        for chunk in nlInputTexts{
                            let rnReturn = getNLTags(text: chunk)
                        }
                    }
                    print("Mysents count = \(allSentences.count)")
                    await MainActor.run {
                        totalCount = allSentences.count
                        appleProgress = Progress(totalUnitCount: Int64(max(allSentences.count, 1)))
                        startTime = Date()
                    }
                    
                    var outSents: [Sentence] = []
                    // MARK: Step 2: iterate over sentences
#if DEBUG
                    let runfive = false
                    if runfive {
                        allSentences = allSentences.count > 5 ? Array(allSentences.prefix(5)) : allSentences}
#endif
                    
                    for sentence in allSentences {
                        let parsedTokens = try pipeline.runOnSentence(sentence, level: maxPipelineStep.rawValue)
                        if runExplicit {
                            print("max requested step == \(maxPipelineStep.rawValue)")
                        }
                        let mySent: Sentence = Sentence(
                            sentID: sentence.id,
                            conllData: parsedTokens,
                            conllMetas:  []
                        )
                        outSents.append(mySent)
                        
                        
                        
                        await MainActor.run {
                            processedCount += 1
                            appleProgress.completedUnitCount = Int64(processedCount)
                        }
                    }
#if DEBUG
                    dumpDetailsForRunExplicit(runExplicit: runExplicit, outSents: outSents, targetFolderURL: targetFolderURL, fileName: fileName)
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

