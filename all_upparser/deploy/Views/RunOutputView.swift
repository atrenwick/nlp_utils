//
//  RunOutputView.swift
//  Tagger
//
//  Created by Adam on 11/09/2026.
//
import SwiftUI

// overview list of runs == parent
struct RunOutputView: View {
    @Environment(AppModel.self) private var model
    @State var showImporter: Bool = false
    @State var runsToCompare: [RunOutput] = []
    @State var alertMessage: String?
    var body: some View {
        @Bindable var model = model
        NavigationStack{
            VStack{
                if model.allRunOutputs.count == 0 {
                    Text("No previous runs for this session\nTo load saved runs, use Load")
                } else {
                    Form{
                        ForEach($model.allRunOutputs){$run in
                            NavigationLink {
                                RunOutputDetailView( run: $run)
                            } label: {
                                Text(makeRunLabel(run: run, num: run.num))
                                    .foregroundStyle(
                                        (runsToCompare.map {$0.runID} ).contains(run.runID) ? .green : .orange)
                            }
                            .contentShape(Rectangle())
                            .swipeActions(edge: .leading){
                                Button(){
                                    addRemoveForComparison(run: run)
                                } label: {
                                    Label("Compare", systemImage: "cat")
                                }
                            }.contentShape(Rectangle())
                                .swipeActions(edge: .trailing){
                                    Button(role: .destructive){
                                        deleteRun(runID: run.runID)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } // end of for each
                        }
                    Section{
                        NavigationLink {
                            TaggingComparisonView(runPair: runsToCompare)
                        } label: {
                            Text("Tagging comp view \(runsToCompare.count)")
                        }
                    }
                }
                }
            }
            .toolbar{  // toolbar insidethe navstack and the sheet its action button will call
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Text("Load")
                    }
                }
            }
            .alert("Error !",
                   isPresented: Binding(
                    get: {alertMessage != nil},
                    set: {if !$0 {alertMessage = nil} } )
            ) { Button("OK", role: .cancel) { }
            } message: { Text(alertMessage ?? "") }
                .sheet(isPresented: $showImporter) {
                    RunSelectorModal { selectedURL in
                        do {
                            let data = try Data(contentsOf: selectedURL)
                            let loadedResult = try JSONDecoder().decode(RunOutput.self, from: data)
                            model.allRunOutputs.append(loadedResult)
                        } catch {
                            print("Failed to decode: \(error)")
                        }
                    }
                }
        }
    }

    func makeRunLabel(run: RunOutput, num: Int) -> String{
         "Run \(num + 1): \(run.runMetas.sourceFileName) | \(run.runMetas.lang) | \(run.runMetas.safeHeaderAttribs.modelArchitecture) | \(run.runMetas.treebank) | \(run.runMetas.exportFormat)"
    }

    /// func to take an already evaluated runID and then do a delete on it, to avoid simultaneous access attempts from getID and deleteItem
    func deleteRun(runID: String){ model.allRunOutputs.removeAll {$0.runID == runID} }
    // add a leading edge swipe to set as run1, run2
    func addRemoveForComparison(run: RunOutput) {
        var existingIDs: [String] = []
        for run in runsToCompare{ existingIDs.append(run.runID) }
        if  existingIDs.contains(run.runID){
            runsToCompare.removeAll {$0.runID == run.runID}
        } else {
            if runsToCompare.count == 2{
                alertMessage = "2 items already present"
            } else {
                runsToCompare.append(run)
            }
        }
    }
}

struct RunOutputDetailView: View{
    @Environment(\.openURL) var openURL
    @Environment(AppModel.self) internal var model
    
    @Binding var run: RunOutput
    @State var hasAppeared: Bool = false
    @State var fileToView: URL? =   nil
    @State var alertMessage: String?
    @State var additionalExportFormat: ExportFormat = .conll
    @State var sentDictOutput: Dictionary<String,[String:ConsolidatedToken]> = [:]
    @State var outputString: String?
    @State var savedURL: URL?
    var exportFormatShowCases: [ExportFormat]{
        ExportFormat.allCases.filter { format in
            format != model.myConfig.exportConfig.selectedExportFormat
        }
    }
    
    var body: some View {
        NavigationStack{
            Form{
                Section("Run \(run.asShortUUID)"){
                    if model.myConfig.inputConfig.inputFileType == .manual{
                        NavigationLink(destination: BuiltSentsViewer()
                        ){
                            Text("Input sents")
                        }
                    } else {
                        NavigationLink(destination: FileViewerView(fileURL: run.runMetas.sourceFileURL)) {
                            Text("Input file : \(run.runMetas.sourceFileName)")
                        }
                    }
                    //inspect output file/s
                    if model.runOutputFileList.count == 1 {
                        NavigationLink(destination: FileViewerView(fileURL: fileToView)) {
                            Text("Output : \(run.runMetas.outputFileName)")
                        }
                    } else {
                        NavigationLink(destination: OutputFileListView()){
                            Text("Output files")
                        }
                    }
                    NavigationLink(destination: RunErrorSummaryView(myConfig: model.myConfig, toksIn: run.runData.tokCount)){
                        Text("Coverage :: \(model.myConfig.outputData.outErrors.count) errors")}
                    Text("Sentence count : \(run.runData.sents.count)")
                    Text("Tok count : \(run.runData.tokCount)")
                    Text("Language : \(run.runMetas.lang)")
                    Text("Treebank : \(run.runMetas.treebank)")
                }
                Section("Additional Export"){
                    HStack{
                        Picker("Format", selection: $additionalExportFormat) {
                            ForEach(exportFormatShowCases) { format in
                                Text(format.rawValue)
                            }
                        }
                        Spacer()
                        AdditionalExportButton( additionalExportFormat: $additionalExportFormat, alertMessage: $alertMessage, run: run)
                    }
                }
                Section("Dictionary"){
                    HStack{
                        Text("make dict")
                        Spacer()
                        Button {
                            do {
                                savedURL = try runXMLWriter()
                            } catch {
                                error
                                print("Error caught @ 180")
                            }
                        } label : {
                            Text("ExportConsolidated")
                        }
                    }.buttonStyle(.borderedProminent)
                }
            }
            .toolbar{
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarSaveButton(run: run, alertMessage: $alertMessage)
                }
            }
            .onAppear{
                if hasAppeared == false{
                    hasAppeared = true
                    if let hasURL = run.runMetas.savedURL{
                        model.runOutputFileList.append(
                            OutputFileListHelper(
                                id: UUID(),
                                runID: run.runMetas.runID,
                                url: hasURL
                            )
                        )
                        fileToView = hasURL
                    }
                }
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: {alertMessage != nil},
                set: {if !$0 {alertMessage = nil}}
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            run.runMetas.unread = false
        }
    }
    
    func runXMLWriter()  throws -> URL? {
        @Bindable var model = model
        guard let folderURL = model.myConfig.exportConfig.targetFolderURL else {
            if model.myConfig.parsingConfig.verbosity.rawValue > 1{ print("Guard 661 fail")
            }
            throw PipelineError.ExportError.outputFolderCreationError
        }
        outputString = makeSentDictionary(runs: model.allRunOutputs, safeHeaderAttribs: run.runMetas.safeHeaderAttribs, processingStatus: run.runMetas.processingStatus)
        guard let outputString else {
            savedURL = nil
            throw PipelineError.ExportError.makeExportContentError
        }
        savedURL = try PipelineServices.ExporterService.exportDataToFile(
            exportContent: outputString,
            customName: run.runID,
            targetFolderURL: model.myConfig.exportConfig.targetFolderURL!,
            exportFormat: .xml,
            verbosity: .level2
        )
        if let savedURL = savedURL{
            return savedURL
        } else {
            return nil
        }
    }
    
    func makeSentDictionary(runs: [RunOutput], safeHeaderAttribs: XmlHeaderAttribs,processingStatus: ProcessingStatus )-> String {
        var currentSentID: String = ""
        var toksInCurrentSent: Dictionary<String,ConsolidatedToken> = [:]
        var sentToTokDict: Dictionary<String,[String:ConsolidatedToken]> = [:]
        var currentToken: ConsolidatedToken
//        var stringStorage: [String] = []
        var currentTokID: String
        for run in runs{
            for sent in run.runData.sents{
                currentSentID = sent.sentID
                if sentToTokDict.keys.contains(currentSentID){
                    toksInCurrentSent = sentToTokDict[currentSentID]!
                } else {
                    toksInCurrentSent = [:]
                    
                }
                for token in sent.conllData{
                    currentTokID = token.unwrappedUUID
                    if toksInCurrentSent.keys.contains(currentTokID){
                        currentToken = toksInCurrentSent[currentTokID]!
                    } else {
                        currentToken = ConsolidatedToken(
                            tokid: token.tokid,
                            tokUUID: token.unwrappedUUID,
                            form: token.form,
                            posData: [],
                            lemmaData: [],
                            featsData: [],
                            headData: [],
                            deprelData: []
                        )
                    }
                    let runDesc = [run.runMetas.safeHeaderAttribs.modelArchitecture, run.runMetas.lang, run.runMetas.treebank].joined(separator: "_")
                    currentToken.posData.append(
                        ConsolidatedAnnotationData(source: "\(runDesc)_pos", value: token.upos == "_" ? token.xpos : token.upos)
                    )
                    currentToken.lemmaData.append(
                        ConsolidatedAnnotationData(source: "\(runDesc)_lemma", value: token.lemma)
                    )
                    currentToken.featsData.append(
                        ConsolidatedAnnotationData(source: "\(runDesc)_feats", value: token.feats)
                    )
                    currentToken.headData.append(
                        ConsolidatedAnnotationData(source: "\(runDesc)_head", value: token.head)
                    )
                    currentToken.deprelData.append(
                        ConsolidatedAnnotationData(source: "\(runDesc)_deprel", value: token.deprel)
                    )
                    toksInCurrentSent[currentTokID] = currentToken
                }
                sentToTokDict[currentSentID] = toksInCurrentSent
            }
        }
        var myStringDump: [String] = []
        var sentNum: Int = 0
        var tokNum: Int = 0
        for key in sentToTokDict.keys{
            sentNum += 1
            myStringDump.append("<s id = \"\(key.xmlEscaped)\" num=\"\(sentNum)\">\n")
            let blob = sentToTokDict[key]!
            let str = blob.values
                .sorted {$0.tokid < $1.tokid}
                .map { $0.asXML}
                .joined(separator: "\n")
            myStringDump.append(str)
            myStringDump.append("\n</s>\n\n")
            tokNum += blob.values.count
        }
        
        let xmlHeader = XMLMakingWorkflow.makeSentDictionaryHeader(
            sentNum: sentNum,
            tokNum: tokNum,
            safeHeaderAttribs: safeHeaderAttribs,
            processingStatus: processingStatus
        )
        
        let xmlFooter = """
        </p>
        </body>
        </text>
        </TEI.2>
        """
        let outputString = [xmlHeader, myStringDump.joined(separator: "\n"), xmlFooter].joined(separator: "\n")
        return outputString
    }
}

// Sheet to appear to choose a previous run to load
struct RunSelectorModal: View {
    @Environment(\.dismiss) var dismiss
    @State private var runFiles: [URL] = []
    @State var runHelpers: [RunSelectorHelper] = []
    let onSelect: (URL) -> Void
    
    var body: some View {
        NavigationStack {
            List(runHelpers, id:\.self.jsonFile){helper in
                Button {
                    onSelect(helper.jsonFile)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        let descTexts = helper.descTexts()
                        Text(descTexts[0])
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(descTexts[1])
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Load saved run")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                loadRunSummaries()
            }
        }
    }

    private func loadRunSummaries() {
        guard let runsDir = try? PipelineServices.ResultStorageManager.getRunsDirectory() else { return }
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: runsDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            let jsonFiles = contents.filter { $0.pathExtension == "json" }
            var runHelpers: [RunSelectorHelper] = []
            for fileURL in jsonFiles {
                if let data = try? Data(contentsOf: fileURL){
                    if let wrapper = try? JSONDecoder().decode(RunFileWrapper.self, from: data) {
                        let newHelper = RunSelectorHelper(runMetas: wrapper.runMetas, jsonFile: fileURL)
                        runHelpers.append(newHelper)
                    }
                }
            }
            self.runHelpers = runHelpers
        } catch {
            print("Failed to list runs directory: \(error)")
        }
    }
}

struct RunErrorSummaryView: View{
    let myConfig: TaggerConfig
    let toksIn: Int
    var errorCases: [OutputError] { myConfig.outputData.outErrors}
    var totalSents: Int {  errorCases.count + myConfig.outputData.outSents.count }
    var totalOutputToks: Int { myConfig.outputData.outSents.reduce(0) {$0 + $1.tokCount}  }
    var sentCoverage: String {
        let intermed = 1 - (Double(errorCases.count) / Double(totalSents))
        return String(format: "%.2f", (intermed * 100))
    }
    var tokCoverage: String {
        if toksIn == 0 || totalOutputToks == 0 {
            return " ??? "
        } else {
            return String(
                format: "%.2f", ( Double(totalOutputToks) / Double(toksIn) * 100 )
            )
        }
    }
    
    var body: some View{
        Form{
            Text("Sents: \(errorCases.count) errors in \(totalSents) sents -> \(sentCoverage) % coverage")
            Text("Toks: \(toksIn) in -> \(totalOutputToks) out :: \(tokCoverage) %")
            ForEach(errorCases.enumerated(), id: \.offset){(num,item) in
                VStack{
                    Text(makeSentStartString(num: num, item: item))
                    HStack{
                        Text(item.errorType.rawValue)
                        Text("Toks: \(item.tokCount) :: Subtoks: \(item.subtokCount)")
                    }
                }
            }
        }
    }
    
    func makeSentStartString(num: Int, item: OutputError)-> String{
        let numStr = String(num+1)
        let tokChunk = item.sentence.tokens.prefix(5).joined(separator: " ")
        return "\(numStr): \(tokChunk)"
    }
}

struct ToolbarSaveButton: View{
    let run: RunOutput
    @Binding var alertMessage: String?
    var body: some View{
        Button{
            do {
                if let savedURL = try PipelineServices.ResultStorageManager.saveRun(run){
                    print("Saved to \(savedURL)")}
            } catch {
                switch error {
                    case let fileSaveError as PipelineError.ExportError:
                        alertMessage = fileSaveError.errorDescription
                    default:
                        alertMessage = error.localizedDescription
                }
            }
        } label: {
            Text("Save")
        }
    }
}

struct AdditionalExportButton: View{
    @Environment(AppModel.self) internal var model
    @Binding var additionalExportFormat: ExportFormat
    @Binding var alertMessage: String?
    let run: RunOutput
    var body: some View{
        Button {
            do {
                let runOutput = try additionalExportRunner(
                    run: run,
                    additionalExportFormat: additionalExportFormat,
                    processingStatus: model.myConfig.progressConfig.processingStatus
                )
                if let hasURL = runOutput.runMetas.savedURL{
                    model.runOutputFileList.append(
                        OutputFileListHelper(
                            id: UUID(),
                            runID: runOutput.runMetas.runID,
                            url: hasURL
                        )
                    )
                }
                model.allRunOutputs.append(runOutput)
            } catch {
                switch error {
                    case let exportError as PipelineError.ExportError:
                        alertMessage = exportError.errorDescription
                    default:
                        alertMessage = error.localizedDescription
                }
            }
        } label: {
            Text("Export")
        }
        .tint(.green)
        .buttonStyle(.borderedProminent)
    }
    
    func additionalExportRunner(
            run: RunOutput,
            additionalExportFormat: ExportFormat,
            processingStatus: ProcessingStatus
        ) throws -> RunOutput {
            @Bindable var model = model
            var newRunNumber: Int = model.runNum
            newRunNumber += 1
            model.runNum = newRunNumber
            
            let exportContent = GeneralOutputMakingWorkflow.makeExportContent(
                headers: run.runMetas.safeHeaderAttribs,
                sents: run.runData.sents,
                exportFormat: additionalExportFormat,
                includeConllSentText: run.runMetas.includeConllSentText,
                processingStatus: processingStatus
                )
            guard !exportContent.isEmpty else {
                print("throw @213")
                throw PipelineError.ExportError.makeExportContentError
            }
            let runData = RunData(
                runID: run.runID,
                sents: run.runData.sents,
                exportContent: exportContent
            )
            let additionalExportParams = AdditionalExportParams(exportFormat: additionalExportFormat, includeConllSentText: run.runMetas.includeConllSentText
            )
            let pipelineRequestForAdditional = PipelineBuildRequest(
                languageCode: Language(rawValue: run.runMetas.lang) ?? Language.FR,
                base: ModelArchitecture(rawValue: run.runMetas.safeHeaderAttribs.modelArchitecture) ?? ModelArchitecture.cnnBiLSTM,
                treebank: Language.Treebank(rawValue: run.runMetas.treebank) ?? Language.Treebank.frTB1
            )
            let runMetas = WritingWorkflow.saveFileToChosenLocation(
                myConfig: model.myConfig,
                exportContent: exportContent,
                pipelineRequest: pipelineRequestForAdditional,
                runID: run.runID,
                processingStatus: model.myConfig.progressConfig.processingStatus,
                additional: additionalExportParams
            )
            let runOutput = RunOutput(num: newRunNumber, runID: run.runID, runData: runData, runMetas: runMetas)
            return runOutput
        }
}
