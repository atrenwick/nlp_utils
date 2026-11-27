//
//  RunSelectorView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI


// Sheet to appear to choose a previous run to load
struct RunSelectorView: View {
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
}

extension RunSelectorView {
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

