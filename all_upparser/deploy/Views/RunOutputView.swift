//
//  RunOutputView.swift
//  Tagger
//
//  Created by Adam on 11/09/2026.
//
import SwiftUI

// detail for each run == child
struct RunOutputDetailView: View{
    @Environment(\.openURL) var openURL

    @Binding var myConfig: TaggerConfig
    @Binding var topLevelOutput: [RunOutput]
    @Binding var run: RunOutput
    @Binding var builtSents: [BuiltSentHolder]
    @Binding var tempTokens: [TempToken]
    @State var runOutputFileList: [OutputFileListHelper] = []
    @State var hasAppeared: Bool = false
    @State var fileToView: URL? =   nil
    @State var alertMessage: String?
    @State var additionalExportFormat: ExportFormat = .conll

    let safeHeaderAttribs: XmlHeaderAttribs
    let runExplicit = true
    
    var shortUUID: String{
        String(Array(run.id.uuidString).suffix(7))
    }
        
    var exportFormatShowCases: [ExportFormat]{
        ExportFormat.allCases.filter { format in
            format != myConfig.exportConfig.selectedExportFormat
        }
    }
    
    var body: some View {
        NavigationStack{
            Form{
                Section("Run \(shortUUID)"){
                    if myConfig.inputConfig.inputFileType == .manual{
                        NavigationLink(destination: BuiltSentsViewer(myConfig: $myConfig, builtSents: $builtSents)
                        ){
                            Text("Input sents")
                        }
                    }
                    else {
                        NavigationLink(destination: FileViewerView(fileURL: run.runMetas.sourceFileURL)) {
                            Text("Input file : \(run.runMetas.sourceFileName)")
                        }
                    }
                    //inspect output file/s
                    if runOutputFileList.count == 1 {
                        NavigationLink(destination: FileViewerView(fileURL: fileToView)) {
                            Text("Output : \(run.runMetas.outputFileName)")
                        }
                    } else {
                        NavigationLink(destination: OutputFileListView(runOutputFileList: runOutputFileList)){
                            Text("Output files")
                        }
                    }
                    NavigationLink(destination: RunErrorSummaryView(myConfig: myConfig, toksIn: run.runData.tokCount)){
                        Text("Coverage :: \(myConfig.outputData.outErrors.count) errors")}
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
                        Button {
                            do{
                                let runOutput = try additionalExportRunner(
                                    run: run,
                                    additionalExportFormat: additionalExportFormat
                                )
                                if let hasURL = runOutput.runMetas.savedURL{
                                    
                                    runOutputFileList.append(
                                        OutputFileListHelper(
                                            id: UUID(),
                                            runID: runOutput.runMetas.runID,
                                            url: hasURL
                                        )
                                        )
                                }
                                topLevelOutput.append(runOutput)
                            } catch {
                                switch error {
                                case let PipelineError as PipelineError:
                                    alertMessage = PipelineError.errorDescription
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
                }
                Section("Save"){
                    HStack{
                        Spacer()
                        Button {
                            do{
                                if let savedURL = try PipelineServices.ResultStorageManager.saveRun(run){
                                    print("Saved to \(savedURL)")}
                            } catch {
                                switch error {
                                case let fileSaveError as PipelineError:
                                    alertMessage = fileSaveError.errorDescription
                                default:
                                    alertMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            Text("Save")
                        }
                    }
                    .tint(.blue)
                    .buttonStyle(.borderedProminent)
                }
            }
            .onAppear{
                if hasAppeared == false{
                    hasAppeared = true
                    if let hasURL = run.runMetas.savedURL{
                        runOutputFileList.append(
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
        )
        {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            run.runMetas.unread = false
        }
    }

    func additionalExportRunner(
        run: RunOutput,
        additionalExportFormat: ExportFormat
    ) throws -> RunOutput {
        
        let exportContent = GeneralOutputMakingWorkflow.makeExportContent(
            headers: run.runMetas.safeHeaderAttribs,
            sents: run.runData.sents,
            exportFormat: additionalExportFormat,
            includeConllSentText: run.runMetas.includeConllSentText
            )
        print("exportformat found= \(additionalExportFormat.rawValue)")
        guard !exportContent.isEmpty else {
            print("throw @213")
            throw PipelineError.ExportError.makeExportContentError }
        
        let runData = RunData(
            runID: run.runID,
            sents: run.runData.sents,
            exportContent: exportContent
        )
        let additionalExportParams = AdditionalExportParams(exportFormat: additionalExportFormat, includeConllSentText: run.runMetas.includeConllSentText)
        let runMetas = WritingWorkflow.saveFileToChosenLocation(myConfig: myConfig, exportContent: exportContent, runID: run.runID, additional: additionalExportParams)
        let runOutput = RunOutput(runID: run.runID, runData: runData, runMetas: runMetas)
        return runOutput
    }
}

// overview list of runs == parent
struct RunOutputView: View {
    @Binding var myConfig: TaggerConfig
    @Binding var runs: [RunOutput]
    let safeHeaderAttribs: XmlHeaderAttribs
    @Binding var builtSents: [BuiltSentHolder]
    @Binding var tempTokens: [TempToken]
    @State var showImporter: Bool = false
    let runExplicit = true

    var body: some View {
        NavigationStack{
            if runs.count == 0 {
                Text("Not much to see here")
            } else {
                NavigationStack{
                    List{
                        ForEach(runs.enumerated(), id:\.offset){num,run in
                            NavigationLink {
                                RunOutputDetailView(
                                    myConfig: $myConfig,
                                    topLevelOutput: $runs,
                                    run: bindingFor(run),
                                    builtSents: $builtSents,
                                    tempTokens: $tempTokens,
                                    safeHeaderAttribs: safeHeaderAttribs
                                )
                            } label: {
                                Text(makeRunLabel(run: run, num: num))
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showImporter) {
            RunSelectorModal { selectedURL in
                do {
                    let data = try Data(contentsOf: selectedURL)
                    let loadedResult = try JSONDecoder().decode(RunOutput.self, from: data)
                    runs.append(loadedResult)
                } catch {
                    print("Failed to decode: \(error)")
                }
            }
        }
        .toolbar{
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Text("Load")
                    }
                }
            }
    }
    func makeRunLabel(run: RunOutput, num: Int) -> String{
        return "Run \(num + 1): \(run.runMetas.sourceFileName) | \(run.runMetas.lang) | \(run.runMetas.treebank) | \(run.runMetas.exportFormat)"
    }
    
    // func to get binding for specific el to pass as write-accessible
    private func bindingFor(_ run: RunOutput) -> Binding<RunOutput> {
            guard let index = runs.firstIndex(where: { $0.id == run.id }) else {
                fatalError("RunOutput not found — shouldn't happen")
            }
            return $runs[index]
        }
}

// choose a previous run to load
struct RunSelectorModal: View {
    @Environment(\.dismiss) var dismiss
    @State private var runFiles: [URL] = []
    let onSelect: (URL) -> Void
    @State var runHelpers: [RunSelectorHelper] = []
    
    var body: some View {
        NavigationStack {
            List(runHelpers, id:\.self.jsonFile){helper in
                Button {
                    onSelect(helper.jsonFile)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(descTexts(helper: helper)[0])
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(descTexts(helper: helper)[1])
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
    private func descTexts(helper: RunSelectorHelper) -> [String] {
        let line1 = String("\(helper.runMetas.sourceFileName) -> \(helper.runMetas.exportFormat.rawValue)")
        let line2 = "\(helper.runMetas.processedCount) sents :: \(helper.runMetas.lang) :: \(helper.runMetas.treebank) :: Steps 2- \(helper.runMetas.maxPipelineStep.rawValue)"
        return [line1, line2]
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
    var totalSents: Int {
        errorCases.count + myConfig.outputData.outSents.count
    }
    var totalOutputToks: Int {
        myConfig.outputData.outSents.reduce(0) {$0 + $1.tokCount}
    }
    var sentCoverage: String {
        let intermed = 1 - (Double(errorCases.count) / Double(totalSents))
        return String(format: "%.2f", (intermed * 100))
    }
    var tokCoverage: String {
        if toksIn == 0 || totalOutputToks == 0 {
            return " ??? "
        } else {
            let intermed = Double(totalOutputToks) / Double(toksIn)
            return String(format: "%.2f", (intermed * 100))
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

