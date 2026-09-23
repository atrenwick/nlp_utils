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
    @State var exportContent: String = ""
    @State var exportStatusMessage: String = ""

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
            format != run.exportFormat
        }
    }
    
    var body: some View {
        NavigationStack{
            Form{
                Section("Run \(shortUUID)"){
                    Text("Input file : \(run.sourceFileName)")
                    NavigationLink(destination: FileViewerView(fileURL: run.outputFileName)) {
                        Text("Output : \(run.outputFileName.lastPathComponent)")
                    }
                    Text("Sentence count : \(run.sents.count)")
                    Text("Tok count : \(run.tokCount)")
                    Text("Language : \(run.lang)")
                    Text("Treebank : \(run.treebank)")
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
                        exportContent = makeExportContent(sentences: run.sents, exportFormat: additionalExportFormat, safeHeaderAttribs:safeHeaderAttribs)
                        print("run.sents.count: \(run.sents.count)")
                        print("chosenformat: \(additionalExportFormat.fileExtension)")
                        print("lang: \(selectedLanguage.rawValue)")
                        print("xmltitlte: \(xmlTitle)")
                        print("xmlauthor: \(xmlAuthor)")
                        print(exportContent)
                        
                        let saveReport = saveFileToChosenLocation(
                            exportContent: exportContent,
                            saveName: fileName,
                            targetFolderURL: targetFolderURL,
                            exportFormat: additionalExportFormat,
                            treebank: selectedTreebank
                        )
                        exportStatusMessage = saveReport.message
                        
                    } label: {
                        Text("Export")
                    }
                    .tint(.green)
                    .buttonStyle(.borderedProminent)
                    .onAppear {
                        run.unread = false
                    }
                }
            }
        }
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
                            RunOutputDetailView(run: bindingFor(run), xmlTitle: $xmlTitle, xmlAuthor: $xmlAuthor, selectedLanguage: $selectedLanguage, targetFolderURL: $targetFolderURL, fileName: $fileName, selectedTreebank: $selectedTreebank, safeHeaderAttribs: safeHeaderAttribs )
                        } label: {
                            Text("Run \(num + 1): \(run.sourceFileName) | \(run.lang) | \(run.treebank) | \(run.exportFormat)")
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
