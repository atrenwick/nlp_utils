//
//  PipelineSettingsView.swift
//  Tagger
//
//  Created by Adam on 08/09/2026.
//
//TODO: A-B choices for tokenisation method, source type, sourcelang
//TODO: output conll : change to std, grid ; std needs to have \t
//TODO: parse from file rather than bundle
//TODO: export, share parsed output

import SwiftUI
internal import UniformTypeIdentifiers


struct PipelineSettingsView: View {
    
    @State var fileContainerModel = SourceFileContainerModel()
    
    @State var fileName: String = "asdkf"
    @State var targetFolderURL: URL? = nil
    @State var selectedOutputPlaform: OutputTarget = .ViewOnly
    @State var selectedLanguage: Language = .FR
    @State var selectedTreebank: Language.Treebank = .frTB1
    @State var maxPipelineStep: PipelineStep = .step4
    @State var inputFileType: InputFileType = .conll
    @State var selectedTokenisationMethod: TokenisationMethod = .conll
    @State var selectedXMLoutputType: XMLOutputType = .xml
    @State var selectedExportFormat: ExportFormat = .xml
    @State var xmlAuthorName: String = "author"
    @State var xmlTitle: String = "title"

    //progressbars::
    @State private var progressBarStyle: ProgressBarStyle = .apple
    @State private var startTime: Date?
    @State private var processedCount = 0
    @State private var totalCount = 0
    @State private var appleProgress = Progress(totalUnitCount: 1)
    @State private var hasStarted = false

    @State private var topLevelOutputList: [RunOutput] = []
    @State var outputString: String = "not yet run"
    @State var taggingInProgress: Bool = false
    
    @State var showImporter: Bool = false
    @State var selectedInputFile: URL? = nil
    
    // for runnning func
    @State private var testSentences: [String] = []
    @State private var errorMessage: String?
    @State private var outputLines: [String] = []
    @State private var conllRawLines: [String] = []
    @State private var conllSentsOut: [ConllSent] = []

    
    @State private var isSelectingFolder = false
    @State private var exportStatusMessage: String?
    
    let runExplicit = false //true // hardcoded bool for testing verbosity, display of test elements

    
    var body: some View {
        
        NavigationStack{
            Form {
                Section{
                    ImportFileViewSection(fileContainerModel: fileContainerModel )
                }
                // First Picker
                Section("Parameters"){
                    Picker("Inputtype", selection: $inputFileType){
                        ForEach(InputFileType.allCases){fType in
                            Text(fType.rawValue)}
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
                    NavigationLink("Select processor steps"){
                        ProcessorStepConfigViewSection(maxActiveStep: $maxPipelineStep, inputFileType: $inputFileType, selectedTokenisationMethod: $selectedTokenisationMethod)
                    }
                }//end section
                ExportConfigViewSection(fileName: $fileName, targetFolderURL: $targetFolderURL, selectedOutputPlaform: $selectedOutputPlaform, selectedExportFormat: $selectedExportFormat)
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
                                tokType: selectedTokenisationMethod,
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
                        RunOutputView(runs: topLevelOutputList, xmlTitle: $xmlTitle, selectedLanguage: $selectedLanguage, xmlAuthor: $xmlAuthorName)
                    } label: {
                        Image(systemName: "book.pages.fill")
                    }
                }
            }
        }
        //
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
        tokType: TokenisationMethod,
        maxPipelineStep: PipelineStep,
        taggingInProgress: Binding<Bool>) {
        taggingInProgress.wrappedValue = true
        let tokType: TokenisationMethod = tokType
        let inputFile = fileContainerModel.localSandboxFileURL
        
        errorMessage = nil
        startTime = nil
        hasStarted = true
        
        outputLines = []
        conllRawLines = []
        conllSentsOut = []

        processedCount = 0
        totalCount = 0
    
//        let inputFile = "\(selectedLanguage)_testConll.txt"
        print("inputFile = \(inputFile)")
        Task {
            do {
                
                let pipeline = try UDPipeline(languageCode: selectedLanguage.rawValue, treebank: selectedTreebank.short)
                var allSentences: [TokenisedSentence] = []

                
                //MARK: TOKENISATION and Sentencisation
                switch tokType {
                case .conll:
                    let testlist1: [[String]] = makeConllLinesFromURL(inputURL: inputFile)
                    let intermedSents: [ConllSent] = makeConllSent(conllLines: testlist1)
//                    var mySents: [TokenisedSentence] = []
                    
                    for sent in intermedSents{
                        let TokSentVers = sent.sentAsTokenisedSentence
                        allSentences.append(TokSentVers)
                    }
                    guard  allSentences.count > 1 else { fatalError("No sentences in conll, baling out")}
                    print("Mysents count = \(allSentences.count)")
//
                    //print(allSentences[0])

                    
                    // this works, but builds toksent from source
//                    intermedTokSents  = getSentsForPipelineFromPretokConll(inputFile: inputFile)
//                    for sentence in intermedTokSents{
//                        allSentences.append(sentence)
//                    }
//                    print(allSentences[0])
//                    print("allSentences count = \(allSentences.count)")
                case .retokenise:
                    // Step 1: tokenize everything with model
                    for sentence in testSentences {
                        allSentences.append(contentsOf: try pipeline.tokenize(sentence))
                    }
                    print("Mode a: \(allSentences.count) sents ")
                }
                
                await MainActor.run {
                    totalCount = allSentences.count
                    appleProgress = Progress(totalUnitCount: Int64(max(allSentences.count, 1)))
                    startTime = Date()
                }

                var lines: [String] = []
                var rawLines: [String] = []
                var outSents: [ConllSent] = []
                // MARK: Step 2: process sentences
                // process one detected sentence at a time

#if DEBUG
                let runfive = false
                if runfive {
                allSentences = allSentences.count > 5 ? Array(allSentences.prefix(5)) : allSentences}
#endif

                for sentence in allSentences {
                    let tokens = try pipeline.runOnSentence(sentence, level: maxPipelineStep.rawValue)
                    
                    let mySent: ConllSent = ConllSent(
                        sentID: sentence.id,
                        conllData: tokens)
                    outSents.append(mySent)
                    lines.append(contentsOf: try pipeline.formatSentence(tokens, mode: "tidy"))
                    rawLines.append(contentsOf: try pipeline.formatSentence(tokens, mode: "raw"))

                    await MainActor.run {
                        processedCount += 1
                        appleProgress.completedUnitCount = Int64(processedCount)
                    }
                }
                if runExplicit{
                print("Printing conllRaw")
                    for sentence in outSents {
                        print(sentence.conllSentRaw)
                    }
                    let seqOutput = outSents.generateExportText()
                    print(seqOutput)
                    if let printPath = targetFolderURL?.path(){
                        print(printPath)
                    } else {
                        print("Problem with print path from URL 274")
                    }
                    
                    print("output name = \(fileName)")
                    //try runWriteCoordinator(lines: lines, rawLines: rawLines)
                    
                    //let conllfileuriltest = try printFromConllSents(outsents: outSents)
                    print("Main actor done, running function 277")
                }
                // run serialise,
                let exportContent = makeExportContent(sentences: outSents, exportFormat: selectedExportFormat, lang: selectedLanguage, xmlTitle: xmlTitle, xmlAuthorName: xmlAuthorName)

                saveFileToChosenLocation(exportContent: exportContent, saveName: fileName, targetFolderURL: targetFolderURL, exportFormat: selectedExportFormat)
                
                let xmldumpstring = sentListToXML(
                    sentences: outSents,
                    selectedLanguage: selectedLanguage,
                    selectedXMLoutputType: selectedXMLoutputType,
                    xmlTitle: xmlTitle,
                    xmlAuthorName: xmlAuthorName)
                    
                    
                print(xmldumpstring)
                await MainActor.run {
                    outputLines.append(contentsOf: lines)
                    conllRawLines.append(contentsOf: rawLines)
                    conllSentsOut.append(contentsOf: outSents)
                    taggingInProgress.wrappedValue = false
                    let currentRunOutput = RunOutput(sents: conllSentsOut, sourceFileName: inputFile! , lang: selectedLanguage.rawValue, treebank: selectedTreebank.short)
                    topLevelOutputList.append(currentRunOutput)
                    print("topLevelOutputList length == \(topLevelOutputList.count)")
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

    func saveFileToChosenLocation(exportContent: String, saveName: String, targetFolderURL: URL?, exportFormat: ExportFormat) {
        guard let folderURL = targetFolderURL else {
            if runExplicit {
                print("Guard 292 fail")
            }
            return
        }
        if runExplicit {
            print("Guard 292 passed")
        }
        do {
            let savedURL = try ExporterService.exportDataToFile(
                exportContent: exportContent,
                customName: saveName,
                targetFolderURL: folderURL,
                exportFormat: selectedExportFormat
            )
            exportStatusMessage = "Successfully exported to \(savedURL.lastPathComponent)"
            if runExplicit {   print(exportStatusMessage)}
        } catch {
            exportStatusMessage = "Export failed: \(error.localizedDescription)"
            if runExplicit {print(exportStatusMessage)}
        }
    }
    
}
func makeExportContent(sentences: [ConllSent], exportFormat: ExportFormat, lang: Language, xmlTitle: String?, xmlAuthorName: String?) -> String{
    var returnString: String = ""
    switch exportFormat {
    case .conll, .conllTxt:
        returnString = sentences.generateExportText()
    case .conllTidy:
        returnString = sentences.generateExportTextTidy()
    case .xml:
        returnString = sentListToXML(
            sentences: sentences,
            selectedLanguage: lang,
            selectedXMLoutputType: .xml,
            xmlTitle: xmlTitle ?? "no_title",
            xmlAuthorName: xmlAuthorName ?? "no_name")
    case .xmlConll:
        //make xml conll
        returnString = sentListToXML(
            sentences: sentences,
            selectedLanguage: lang,
            selectedXMLoutputType: .xmlConll,
            xmlTitle: xmlTitle ?? "no_title",
            xmlAuthorName: xmlAuthorName ?? "no_name")
    }
    return returnString
}

#Preview {
    PipelineSettingsView()
}



extension PipelineSettingsView {
    // 1. Array of missing configuration items
    var missingRequirements: [String] {
        var missing: [String] = []
        
        // Rule 1: Check input file exists in sandbox
        if fileContainerModel.localSandboxFileURL == nil {
            missing.append("Input File")
        }
        // TODO: add rule for input type when adding option for non-conll import

        
        // Rule 2: Check custom output filename is typed
        if fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Output Filename")
        }
        
        // Rule 3: Check target folder (or destination setting)
        if targetFolderURL == nil {
            missing.append("Export Directory")
        }
        
        return missing
    }

    // 2. Boolean check for the .disabled() modifier
    var isPipelineReady: Bool {
        return missingRequirements.isEmpty
    }

    // 3. User-friendly warning message
    var missingRequirementsMessage: String {
        guard !missingRequirements.isEmpty else { return "" }
        
        if missingRequirements.count == 1 {
            return "Please set: \(missingRequirements[0])"
        } else {
            // Lists items cleanly: "Missing required settings: Input File, Output Filename, Export Directory"
            return "Missing required settings: \(missingRequirements.joined(separator: ", "))"
        }
    }
}

func sentListToXML(
    sentences: [ConllSent],
    selectedLanguage: Language,
    selectedXMLoutputType: XMLOutputType,
    xmlTitle: String,
    xmlAuthorName: String,

) -> String {
    let xmlSafeLang = selectedLanguage.displayName.lowercased()
    let xmlSafeXMLTitle = xmlTitle.xmlEscaped != "" ? xmlTitle.xmlEscaped : "title"
    let xmlSafeXMLAuthor = xmlAuthorName.xmlEscaped != "" ? xmlAuthorName.xmlEscaped : "author_unknown"
    
    
    let xmlHeader = """
        <?xml version="1.0" encoding="utf-8"?>
          <TEI.2>
          <teiHeader>
            <fileDesc>
            <titleStmt>
            <title>\(xmlSafeXMLTitle)</title>
            <author>\(xmlSafeXMLAuthor))</author>
            </titleStmt>
            <publicationStmt>
            <publisher />
            <date />
            <pubDate />
            </publicationStmt>
                <sourceDesc details="">
                <p />
                </sourceDesc>
            </fileDesc>
            <profileDesc>
                <langUsage>
                <language ident="\(xmlSafeLang)" />
                </langUsage>
            <textDesc thema=\"\" type="review" sub_genre=\"\" />
            </profileDesc>
        </teiHeader>
        <text>
        <body>
        <p>        
        """
    let xmlFooter = """
        </p>
        </body>
        </text>
        </TEI.2>
        """
    var outputStore: [String] = []
    outputStore.append(xmlHeader)
    for sentence in sentences {
        outputStore.append(sentence.makeXMLsent(xmlOutputType: selectedXMLoutputType))
    }
    outputStore.append(xmlFooter)
    
    return outputStore.joined(separator: "\n")
    
}
