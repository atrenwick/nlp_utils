//
//  RunOutputView.swift
//  Tagger
//
//  Created by Adam on 11/09/2026.
//

import SwiftUI

struct RunOutputDetailView: View{
    let run: RunOutput
    @State var additionalExportContent: String = ""
    @Binding var xmlTitle: String
    @Binding var xmlAuthor: String
    @Binding var selectedLanguage: Language
    @State var exportStatusMessage: String = ""
    @State var additionalExportFormat: ExportFormat = .conll
    let runExplicit = true
    var body: some View {
        Form{
            Text("Source file processed : \(run.sourceFileName.path())")
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
            additionalExportContent = makeExportContent(sentences: run.sents, exportFormat: additionalExportFormat, lang: selectedLanguage, xmlTitle: xmlTitle, xmlAuthorName: xmlAuthor)
            
            
        } label: {
            Text("Export CoNLL")
        }
        .tint(.orange)
        .buttonStyle(.borderedProminent)
    }


    func saveFileToChosenLocation(additionalExportContent: String, saveName: String, targetFolderURL: URL?, selectedExportFormat: ExportFormat) {
        
        guard let folderURL = targetFolderURL else {
            if runExplicit {
                print("Guard 31 fail")
            }
            return
        }
        if runExplicit {
            print("Guard 31 passed")
        }
        do {
            let savedURL = try ExporterService.exportDataToFile(
                exportContent: additionalExportContent,
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

struct RunOutputView: View {
    let runs: [RunOutput]
    let runExplicit = true
    @Binding var xmlTitle: String
    @Binding var selectedLanguage: Language
    @Binding var xmlAuthor: String
    @State var exportStatusMessage: String = ""
    var body: some View {
        if runs.count == 0{
            Text("Not much to see here")
        }
        else {
            NavigationStack{
                List{
                    
                    //                    ForEach(Array(sortedEVAS.enumerated()), id:\.offset){num, evaKey in
                    
                    ForEach(runs.enumerated(), id:\.offset){num,run in
                        NavigationLink {
                            RunOutputDetailView(run: run, xmlTitle: $xmlTitle, xmlAuthor: $xmlAuthor, selectedLanguage: $selectedLanguage)
                        } label: {
                            Text("Run \(num + 1)")
                        }
                        
                    }
                }
            }
        }
    }
    
    
}

