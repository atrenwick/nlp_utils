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
    @State var runOutputFileList: [URL] = []
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
                                    runOutputFileList.append(hasURL)
                                }
                                topLevelOutput.append(runOutput)
                            } catch {
                                switch error {
                                case let parseProcessingError as ParseProcessingError:
                                    alertMessage = parseProcessingError.errorDescription
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
                                if let savedURL = try ResultStorageManager.save(run){
                                    print("Saved to \(savedURL)")}
                            } catch {
                                switch error {
                                case let fileSaveError as ParseProcessingError:
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
                        runOutputFileList.append(hasURL)
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
        run:RunOutput,
        additionalExportFormat: ExportFormat
    ) throws -> RunOutput {
        
        let exportContent = makeExportContentFromMetas(run: run, additionalExportFormat: additionalExportFormat)
        guard !exportContent.isEmpty else { throw ParseProcessingError.makeExportContentError }
        
        let runData = RunData(
            runID: run.runID,
            sents: run.runData.sents,
            exportContent: exportContent
        )

        let runMetas = saveFileToChosenLocation(myConfig: myConfig, exportContent: exportContent, runID: run.runID,)
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
    func descTexts(helper: RunSelectorHelper) -> [String] {
        let line1 = String("\(helper.runMetas.sourceFileName) -> \(helper.runMetas.exportFormat.rawValue)")
        let line2 = "\(helper.runMetas.processedCount) sents :: \(helper.runMetas.lang) :: \(helper.runMetas.treebank) :: Steps 2- \(helper.runMetas.maxPipelineStep.rawValue)"
        return [line1, line2]
    }

    private func loadRunSummaries() {
        guard let runsDir = try? ResultStorageManager.getRunsDirectory() else { return }
        
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

