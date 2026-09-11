//
//  ChildViews.swift
//  Tagger
//
//  Created by Adam on 10/09/2026.
// :: child views which get rendered in parent view :: all have ViewSection as part of name

import SwiftUI
internal import UniformTypeIdentifiers

struct ExportConfigViewSection: View {
    @State private var isSelectingFolder: Bool = false
    @State private var isProcessing: Bool = false
    
    @Binding var fileName: String
    @Binding var targetFolderURL: URL?
    @Binding var selectedOutputPlaform: OutputTarget
    @Binding var selectedExportFormat: ExportFormat

    var body: some View {
        //        Form {
        Section("Export Configuration") {
            //0 set format
            Picker("Export (sub)type", selection: $selectedExportFormat){
                ForEach(ExportFormat.allCases){ formatOption in
                    Text(formatOption.rawValue)
                    
                }
            }
            // 1. User types the filename
            FileNameInputView(fileName: $fileName, selectedExportFormat: selectedExportFormat)
            
            // 2. User chooses the target folder
            HStack {
                Text("Destination:")
                Spacer()
                Text(targetFolderURL?.lastPathComponent ?? "Not Selected")
                    .foregroundColor(.secondary)
                Button("Choose...") {
                    isSelectingFolder = true
                }
            }
            Picker("Output for…", selection: $selectedOutputPlaform) {
                ForEach(OutputTarget.allCases) { outputTarget in
                    Text(outputTarget.rawValue)
                }
            }
        }
        // Folder Selection System Sheet
        .fileImporter(
            isPresented: $isSelectingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Gain security access to folder
                    if url.startAccessingSecurityScopedResource() {
                        self.targetFolderURL = url
                    }
                }
            case .failure(let error):
                print("Folder selection error: \(error.localizedDescription)")
            }
        }
    }
}

struct ChooseInputFileViewSection: View {
    // for choosing the source file to get, parse
    @State private var isSelectingFile: Bool = false
    @Binding var selectedInputFile: URL?
    
    var body: some View {
        
            // User chooses the target folder
            HStack {
                Text("Source:")
                Spacer()
                Text(selectedInputFile?.lastPathComponent ?? "Not Selected")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Button {
                        isSelectingFile = true
                    } label: {
                        Image(systemName: selectedInputFile == nil ? "folder" : "arrow.triangle.2.circlepath")
                    }
                //                Text(selectedInputFile?.lastPathComponent ?? "Not Selected")
//                    .foregroundColor(.secondary)
//                Button("Choose...") {
//                    isSelectingFile = true
//                }
            }

        // Folder Selection System Sheet
        .fileImporter(
            isPresented: $isSelectingFile,
            allowedContentTypes: [.json, .plainText, .xml, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    // hand off to your pipeline here
                } catch {
                    print("Failed to read file: \(error)")
                }
            case .failure(let error):
                print("Folder selection error: \(error.localizedDescription)")
            }
        }
    }
}


struct FileNameInputView: View {
    // for adding outout file name
    @Binding var fileName: String
    @FocusState private var isFocused: Bool
    let selectedExportFormat: ExportFormat
    
    // Set of characters prohibited in file names across major file systems
    
    var body: some View {
        HStack{
            TextField("File name", text: $fileName)
                .textInputAutocapitalization(TextInputAutocapitalization.never)
                .autocorrectionDisabled()
                .onChange(of: fileName) { _, newValue in
                    // Strip any forbidden characters immediately as typed or pasted
                    let cleaned = fileName.sanitizedFileName
                    if cleaned != newValue {
                        fileName = cleaned
                    }
                }
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit {
                    isFocused = false
                }
            Text(selectedExportFormat.fileExtension).foregroundStyle(.secondary)
        }
        
    }
    func getFullURL(in folderURL: URL) -> URL {
        // 1. Fallback to a default name if user left it blank
        let cleanName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanName.isEmpty ? "Untitled" : cleanName
        
        // 2. Append the extension (e.g., .json or .txt)
        return folderURL
            .appendingPathComponent(finalName)
            .appendingPathExtension("json")
    }

}


struct OutputLinesViewSection: View {
    let outputLines: [String]
    
    private var visibleSents: [String] {
        Array(outputLines.prefix(50))
    }

    var body: some View{
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(visibleSents.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }
}


struct PretokenisedSentViewSection : View {
    let pretokSentsOut: [TokenisedSentence]
    var body: some View{
        ScrollView{
            ForEach(pretokSentsOut, id:\.self){instance in
                Text("moo")
                ForEach(instance.tokens, id:\.self){tok in
                Text(tok)}
            }
        }
    }
}

