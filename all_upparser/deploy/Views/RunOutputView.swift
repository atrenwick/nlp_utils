//
//  RunOutputView.swift
//  Tagger
//
//  Created by Adam on 11/09/2026.
//


import SwiftUI
struct RunOutputDetailView: View{
    @Environment(\.openURL) var openURL

    @State var additionalExportFormat: ExportFormat = .conll
    @State var exportStatusMessage: String = ""
    @State var runOutputFileList: [URL] = []
    @State var hasAppeared: Bool = false
    @State var fileToView: URL? =   nil
    @State var alertMessage: String?
    
    @Binding var topLevelOutput: [RunOutput]
    @Binding var run: RunOutput
    @Binding var xmlTitle: String
    @Binding var xmlAuthor: String
    @Binding var selectedLanguage: Language
    @Binding var targetFolderURL: URL?
    @Binding var fileName: String
    @Binding var selectedTreebank: Language.Treebank
    
    let safeHeaderAttribs: XmlHeaderAttribs
    let runExplicit = true
    
    var shortUUID: String{
        String(Array(run.id.uuidString).suffix(7))
    }
        
    var exportFormatShowCases: [ExportFormat]{
        ExportFormat.allCases.filter { format in
            format != run.runMetas.exportFormat
        }
    }
    
    var body: some View {
        NavigationStack{
            Form{
                Section("Run \(shortUUID)"){
                    NavigationLink(destination: FileViewerView(fileURL: run.runMetas.sourceFileURL)) {
                        Text("Input file : \(run.runMetas.sourceFileName)")
                    }
                    
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
        Form{
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
                                additionalExportFormat: additionalExportFormat,
                                selectedLanguage: selectedLanguage,
                                selectedTreebank: selectedTreebank
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
    }
    func additionalExportRunner(
        run:RunOutput,
        additionalExportFormat: ExportFormat,
        selectedLanguage: Language,
        selectedTreebank: Language.Treebank
    ) throws -> RunOutput {
        
        let exportContent = makeExportContent(
            sentences: run.runData.sents,
            exportFormat: additionalExportFormat,
            safeHeaderAttribs:run.runMetas.safeHeaderAttribs
        )
//        print("run.sents.count: \(run.runData.sents.count)")
//        print("chosenformat: \(additionalExportFormat.fileExtension)")
//        print("lang: \(selectedLanguage.rawValue)")
//        print(exportContent)
        
        guard !exportContent.isEmpty else {
            throw ParseProcessingError.makeExportContentError
        }
        
        let runData = RunData(
            sents: run.runData.sents,
            exportContent: exportContent
        )
        let updatedInputMetas = SaveInputMetas(
            lang: selectedLanguage,
            displayName: run.runMetas.sourceFileName,
            inputURL: run.runMetas.sourceFileURL,
            saveName: run.runMetas.outputFileName,
            targetFolderURL: run.runMetas.savedURL?.deletingLastPathComponent(),
            exportFormat: additionalExportFormat,
            treebank: selectedTreebank ,
            safeHeaderAttribs: run.runMetas.safeHeaderAttribs
        )
        
        let runMetas = saveFileToChosenLocation(exportContent: exportContent, saveInputMetas: updatedInputMetas)
        let runOutput = RunOutput(runData: runData, runMetas: runMetas)

        return runOutput
    }

}


struct RunOutputView: View {
    @State var exportStatusMessage: String = ""
    
    @Binding var runs: [RunOutput]
    @Binding var xmlTitle: String
    @Binding var selectedLanguage: Language
    @Binding var xmlAuthor: String
    @Binding var targetFolderURL: URL?
    @Binding var fileName: String
    @Binding var selectedTreebank: Language.Treebank
    
    let runExplicit = true
    let safeHeaderAttribs: XmlHeaderAttribs

    var body: some View {
        if runs.count == 0 {
            Text("Not much to see here")
        } else {
            NavigationStack{
                List{
                    ForEach(runs.enumerated(), id:\.offset){num,run in
                        NavigationLink {
                            RunOutputDetailView(
                                topLevelOutput: $runs,
                                run: bindingFor(run),
                                xmlTitle: $xmlTitle,
                                xmlAuthor: $xmlAuthor,
                                selectedLanguage: $selectedLanguage,
                                targetFolderURL: $targetFolderURL,
                                fileName: $fileName,
                                selectedTreebank: $selectedTreebank,
                                safeHeaderAttribs: safeHeaderAttribs
                            )
                        } label: {
                            Text("Run \(num + 1): \(run.runMetas.sourceFileName) | \(run.runMetas.lang) | \(run.runMetas.treebank) | \(run.runMetas.exportFormat)")
                        }
                    }
                }
            }
        }
    }
    // func to get binding for specific el to pass as write-accessible
    private func bindingFor(_ run: RunOutput) -> Binding<RunOutput> {
            guard let index = runs.firstIndex(where: { $0.id == run.id }) else {
                fatalError("RunOutput not found — shouldn't happen")
            }
            return $runs[index]
        }
}
