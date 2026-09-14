//
//  RunOutputView.swift
//  Tagger
//
//  Created by Adam on 11/09/2026.
//

import SwiftUI

struct RunOutputDetailView: View{

    @Binding var run: RunOutput
    @State var exportContent: String = ""
    @Binding var xmlTitle: String
    @Binding var xmlAuthor: String
    @Binding var selectedLanguage: Language
    @Binding var targetFolderURL: URL?
    @Binding var fileName: String
    @State var exportStatusMessage: String = ""
    @State var additionalExportFormat: ExportFormat = .conll
    let runExplicit = true
    var body: some View {
        Form{
            Text("Input file : \(run.sourceFileName.lastPathComponent)")
            Text("Output file : \(run.outputFileName.lastPathComponent)")
            Text("Sentence count : \(run.sents.count)")
            Text("Tok count : \(run.tokCount)")
            Text("Language : \(run.lang)")
            Text("Treebank : \(run.treebank)")
            
        }
        Picker("Export format", selection: $additionalExportFormat) {
            ForEach(ExportFormat.allCases) { format in
                Text(format.rawValue)
            }
        }
        
        
        Button {
            
            exportContent = makeExportContent(sentences: run.sents, exportFormat: additionalExportFormat, lang: selectedLanguage, xmlTitle: xmlTitle, xmlAuthorName: xmlAuthor)
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
                exportFormat: additionalExportFormat
            )
            exportStatusMessage = saveReport.message
            
        } label: {
            Text(additionalExportFormat.fileExtension)
        }
        .tint(.orange)
        .buttonStyle(.borderedProminent)
        .onAppear {
            run.unread = false
        }
    }
    
    


//    func saveFileToChosenLocation(exportContent: String, saveName: String, targetFolderURL: URL?, exportFormat: ExportFormat) {
//        guard let folderURL = targetFolderURL else {
//            if runExplicit {
//                print("Guard 31 fail")
//            }
//            return
//        }
//        if runExplicit {
//            print("Guard 31 passed")
//        }
//        do {
//            let savedURL = try ExporterService.exportDataToFile(
//                exportContent: additionalExportContent,
//                customName: "\(saveName)_\(exportFormat.rawValue)",
//                targetFolderURL: folderURL,
//                exportFormat: exportFormat
//            )
//            exportStatusMessage = "Successfully exported to \(savedURL.lastPathComponent)"
//            if runExplicit {   print(exportStatusMessage)}
//        } catch {
//            exportStatusMessage = "Export failed: \(error.localizedDescription)"
//            if runExplicit {print(exportStatusMessage)}
//        }
//    }
    
}

struct RunOutputView: View {
    @Binding var runs: [RunOutput]
    let runExplicit = true
    @Binding var xmlTitle: String
    @Binding var selectedLanguage: Language
    @Binding var xmlAuthor: String
    @Binding var targetFolderURL: URL?
    @Binding var fileName: String
    @State var exportStatusMessage: String = ""
    var body: some View {
        if runs.count == 0{
            Text("Not much to see here")
        }
        else {
            NavigationStack{
                List{
                    ForEach(runs.enumerated(), id:\.offset){num,run in
                        NavigationLink {
                            RunOutputDetailView(run: bindingFor(run), xmlTitle: $xmlTitle, xmlAuthor: $xmlAuthor, selectedLanguage: $selectedLanguage, targetFolderURL: $targetFolderURL, fileName: $fileName )
                        } label: {
                            Text("Run \(num + 1): \(run.sourceFileName.deletingPathExtension().lastPathComponent) | \(run.lang) | \(run.treebank) | \(run.exportFormat)")
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

