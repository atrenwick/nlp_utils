//
//  PipelineSettingsView.swift
//  Tagger
//
//  Created by Adam on 08/09/2026.
//
//TODO: A-B choices for tokenisation method, source type, sourcelang

//TODO: view output files

import SwiftUI
internal import UniformTypeIdentifiers


struct PipelineSettingsView: View {
    
    // input file
    @State var fileContainerModel = SourceFileContainerModel()
    @State var selectedInputFile: URL? = nil
    @State var inputFileType: InputFileType = .conll

    // import, parsing settings
    @State var selectedLanguage: Language = .FR
    @State var selectedTreebank: Language.Treebank = .frTB1
    @State var maxPipelineStep: PipelineStep = .step5
    @State var runRetokeniser: Bool = false
    @State var selectedRetokenisationType: RetokenisationType = .predict

    // export settings
    @State var fileName: String = "Filename"
    @State var targetFolderURL: URL? = nil
    @State var selectedExportFormat: ExportFormat = .xml
    @State var xmlAuthorName: String = "XML Author"
    @State var xmlTitle: String = "XML Title"

    //progressbars::
    @State private var appleProgress = Progress(totalUnitCount: 1)
    @State private var progressBarStyle: ProgressBarStyle = .apple
    @State private var startTime: Date?
    @State private var processedCount = 0
    @State private var totalCount = 0
    @State private var hasStarted = false

    // reporting
    @State private var errorMessage: String?
    @State private var saveReport: SaveReport?
    @State private var topLevelOutputList: [RunOutput] = []
    @State private var exportStatusMessage: String?
    @State var outputString: String = "not yet run"

    //controlling visibility
    @State var taggingInProgress: Bool = false
    @State var showImporter: Bool = false
    @State private var isSelectingFolder = false
    
    
    // sentences ::
    @State var builtSents: [HashableSentence] = []
    @State var sentsOut: [Sentence] = []
    @State var sentsToRetokenise: [String] = []
    @State private var testSentences = ["Paris est la capitale de la France.", "La capitale de l'Allemagne est Berlin, mais avant, c'était Bonn mais on trouvait que c'était pas bon.", "Paris est une grande ville française"]
    @State private var newSentence: String = ""

    
    let runExplicit = false //true // hardcoded bool for testing verbosity, display of test elements

    var unreadCount: Int {
        topLevelOutputList.reduce(0) { $1.unread ? $0 + 1 : $0 }
    }
    
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

        let outputStruct = XmlHeaderAttribs(
            xmlTitle: xmlSafeXMLTitle,
            xmlAuthorName: xmlSafeXMLAuthor,
            lang: xmlSafeLang,
            treebank: xmlsafeTreebank,
            taggingDate: xmlsafeDate,
            sourceFile: xmlsafeSourceFile,
            runID: runID,
        )
        return outputStruct
    }
    
    
    var body: some View {
        
        NavigationStack{
            Form {
                if inputFileType != .manual {
                    Section{
                        ImportFileViewSection(fileContainerModel: fileContainerModel )
                    }
                }
                // First Picker
                Section("Parameters"){
                    Picker("Inputtype", selection: $inputFileType){
                        ForEach(InputFileType.allCases){fType in
                            Text(fType.rawValue)}
                    }
                    if inputFileType == .manual{
                        NavigationLink("Manual entry…"){
                            ManualTokenisationView(builtSents: $builtSents)
                        }
                    }
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(Language.allCases) { lang in
                            Text(lang.rawValue) // Displays "EN", "FR"
                        }
                    }
                    .onChange(of: selectedLanguage) { _, newLang in
                        if let first = newLang.availableTBs.first {
                            selectedTreebank = first
                        }
                    }
                    // Model picker, dynamically updating based on Lang picker
                    Picker("Treebank", selection: $selectedTreebank) {
                        ForEach(selectedLanguage.availableTBs) { tb in
                            Text(tb.short).tag(tb)
                        }
                    }
                    .onChange(of: selectedLanguage) { _, newLang in
                                    // Automatically update selected tb to language default
                                    selectedTreebank = newLang.defaultTB
                                }
                    NavigationLink("Select processor steps"){
                        ProcessorStepConfigViewSection(
                            maxActiveStep: $maxPipelineStep,
                            inputFileType: $inputFileType,
                            runRetokeniser: $runRetokeniser,
                            selectedRetokenisationType: $selectedRetokenisationType
                        )
                    }
                }//end section
                ExportConfigViewSection(fileName: $fileName, targetFolderURL: $targetFolderURL,  selectedExportFormat: $selectedExportFormat, xmlAuthorName: $xmlAuthorName, xmlTitle: $xmlTitle)
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
                Section {
                    // 3. User hits 'Go'
                    
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
                    Button(
                        action:{
                            runTagging(
                                inputFileType: inputFileType,
                                maxPipelineStep: maxPipelineStep,
                                taggingInProgress: $taggingInProgress) }){
                                    ZStack {
                                        HStack {
                                            Image(systemName: "play.fill")
                                            
                                            Text("Run")
                                                .fontWeight(.semibold)
                                        }
                                        .opacity(taggingInProgress ? 0 : 1)
                                    }
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(taggingInProgress || !isPipelineReady)
                                .animation(.easeInOut(duration: 0.2), value: isPipelineReady)
                                .padding()
                    
                    if hasStarted {
                        PipelineProgressView(
                            style: progressBarStyle,
                            processed: processedCount,
                            total: totalCount,
                            startTime: startTime,
                            appleProgress: appleProgress
                        )
                    }
                }
            }.toolbar{
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

    
    #if DEBUG
    func testInstantiatePipeline(languageCode: String, treebank: String)   -> String {
        // test instantiation of pipeline class based on params chosen
        outputString = ""
        
        Task{
            do {
                let testPipeline = try UDPipeline(languageCode: selectedLanguage.rawValue, treebank: selectedTreebank.short)
                await MainActor.run {
                    outputString = "Success"
                }
            } catch{
                await MainActor.run {
                    outputString = "Fail : \(error.localizedDescription)"
                }
            }
        }
        return outputString
    }
    #endif

    private func runTagging(
        inputFileType: InputFileType,
        maxPipelineStep: PipelineStep,
        taggingInProgress: Binding<Bool>) {
            //MARK: parameters, initialisations for task
            taggingInProgress.wrappedValue = true

            let inputFileType: InputFileType = inputFileType
            let inputFile = fileContainerModel.localSandboxFileURL
            let displayName: String
            
            switch inputFileType {
            case .manual:
                displayName = "Manual entry"
            case .conll, .xmlConll, .xml, .txt:
                displayName = fileContainerModel.localSandboxFileURL?.lastPathComponent ?? "No file selected"
            } // end switch
            errorMessage = nil
            startTime = nil
            hasStarted = true
            sentsOut = []
            processedCount = 0
            totalCount = 0
    
            
        Task {
            // MARK: tagging :
            do {
                // get pipeline object
                let pipeline = try UDPipeline(languageCode: selectedLanguage.rawValue, treebank: selectedTreebank.short)
                var allSentences: [HashableSentence] = []
                
                //MARK: INGEST SENTS ::
                // TOKENISATION and Sentencisation
                //sents = sents from tokeniser
                // pipeline.runOnSentence([HashableSent])-> [Sentence]
                
                switch inputFileType {
                case .conll:
                    allSentences = conllFileToHashableSentForPipeline(inputURL: inputFile)
                    
                case .manual:
                    allSentences = builtSents
                    
                case .xml:
                    allSentences = xmlToHashableSentForPipeline(inputURL: inputFile)
                    
                case .xmlConll:
                    allSentences = xmlConllFileToHashableSentForPipeline(inputURL: inputFile)
                    
                case .txt:
                    // Step 1: tokenize everything with model
                    for sentence in testSentences {
                        allSentences.append(contentsOf: try pipeline.tokenize(sentence))
                    }
                    print("Mode a: \(allSentences.count) sents ")
                    selectedRetokenisationType = .skip
                }
                
                if runRetokeniser {
                    //actions
                    print("Retokenising")
                    switch selectedRetokenisationType{
                    case .predict:
                        let inputSents = allSentences
                        allSentences.removeAll()
                        for sentence in inputSents {
                            let retokSent = try pipeline.tokenize(sentence.detokenised)
                            allSentences.append(contentsOf: retokSent)
                            if runExplicit {
                                print("max requested step == \(maxPipelineStep.rawValue)")
                            }
                        }
                    case .manual, .rule, .skip:
                        print("In manual mode, usin")
                        break
                    }
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
                
                guard  allSentences.count > 0 else {
                    print("No sentences found, baling out… 🪂")
                    return
                }
                print("Mysents count = \(allSentences.count)")
                
                await MainActor.run {
                    totalCount = allSentences.count
                    appleProgress = Progress(totalUnitCount: Int64(max(allSentences.count, 1)))
                    startTime = Date()
                }
                
                var outSents: [Sentence] = []
                // MARK: Step 2: process sentences
                // process one detected sentence at a time
                
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
                        conllData: parsedTokens
                    )
                    outSents.append(mySent)
                    
                    await MainActor.run {
                        processedCount += 1
                        appleProgress.completedUnitCount = Int64(processedCount)
                    }
                }
                if runExplicit{
                    print("Printing conllRaw")
                    for sentence in outSents {
                        print(sentence.conll)
                    }
                    let seqOutput = outSents.generateExportText()
                    print(seqOutput)
                    if let printPath = targetFolderURL?.path(){
                        print(printPath)
                    } else {
                        print("Problem with print path from URL 274")
                    }
                    print("output name = \(fileName)")
                    print("Main actor done, running function 277")
                }
                
                let exportContent = makeExportContent(sentences: outSents, exportFormat: selectedExportFormat, safeHeaderAttribs: safeHeaderAttribs)
                
                saveReport = saveFileToChosenLocation(exportContent: exportContent, saveName: fileName, targetFolderURL: targetFolderURL, exportFormat: selectedExportFormat, treebank: selectedTreebank)
                
                let xmldumpstring = sentListToXML(
                    sentences: outSents,
                    selectedExportFormat: selectedExportFormat,
                    safeHeaderAttribs:  safeHeaderAttribs
                )
                
                if runExplicit {print(xmldumpstring) }
                
                await MainActor.run {
                    sentsOut.append(contentsOf: outSents)
                    taggingInProgress.wrappedValue = false
                    
                    guard let saveReport else { return }
                    if let savedURL = saveReport.savedURL{
                        let currentRunOutput = RunOutput(
                            sents: sentsOut,
                            sourceFileName: displayName,
                            outputFileName: savedURL,
                            lang: selectedLanguage.rawValue,
                            treebank: selectedTreebank.short,
                            exportFormat: selectedExportFormat
                        )
                        topLevelOutputList.append(currentRunOutput)
                    }
                    if runExplicit{
                        print("topLevelOutputList length == \(topLevelOutputList.count)")
                    }
                }
            } catch {
                print(error.localizedDescription)
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    taggingInProgress.wrappedValue = false
                }
            }
        }
    }
}

#Preview {
    PipelineSettingsView()
}
