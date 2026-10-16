//
//  RunOutputView.swift
//  Tagger
//
//  Created by Adam on 11/09/2026.
//


import SwiftUI
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
    }
    func additionalExportRunner(
        run:RunOutput,
        additionalExportFormat: ExportFormat,
    ) throws -> RunOutput {
        
        let exportContent = makeExportContentFromMetas(run: run, additionalExportFormat: additionalExportFormat)
        
        guard !exportContent.isEmpty else {
            throw ParseProcessingError.makeExportContentError
        }
        
        let runData = RunData(
            runID: run.runID,
            sents: run.runData.sents,
            exportContent: exportContent
        )
//        let updatedInputMetas = SaveInputMetas(
//            lang: selectedLanguage,
//            displayName: run.runMetas.sourceFileName,
//            inputURL: run.runMetas.sourceFileURL,
//            saveName: run.runMetas.outputFileName,
//            targetFolderURL: run.runMetas.savedURL?.deletingLastPathComponent(),
//            exportFormat: additionalExportFormat,
//            treebank: selectedTreebank ,
//            safeHeaderAttribs: run.runMetas.safeHeaderAttribs,
//            includeConllSentText:run.runMetas.includeConllSentText
//        )
        let runMetas = saveFileToChosenLocation(myConfig: myConfig, exportContent: exportContent, runID: run.runID,)
        let runOutput = RunOutput(runID: run.runID, runData: runData, runMetas: runMetas)

        return runOutput
    }
}


struct RunOutputView: View {
    @Binding var myConfig: TaggerConfig
    @Binding var runs: [RunOutput]
    let safeHeaderAttribs: XmlHeaderAttribs
    @Binding var builtSents: [BuiltSentHolder]
    @Binding var tempTokens: [TempToken]

    let runExplicit = true
    var body: some View {
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
