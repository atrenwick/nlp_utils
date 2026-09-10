//
//  ImportFileView.swift
//  Tagger
//
//  Created by Adam on 10/09/2026.
//

import SwiftUI
internal import UniformTypeIdentifiers


struct ImportFileViewSection: View {
    @Bindable var fileContainerModel: SourceFileContainerModel
    @State private var isSelectingFile = false
    
    var body: some View {
        HStack(spacing: 16) {
            if let localURL = fileContainerModel.localSandboxFileURL {
                Text("Selected: \(localURL.lastPathComponent)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Select Input File") {
                isSelectingFile = true
            }
            .fileImporter(
                isPresented: $isSelectingFile,
                allowedContentTypes: [.item], // Accepts any file type
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let externalURL = urls.first else { return }
                    
                    // 1. Gain temporary sandbox access to external file
                    let gotAccess = externalURL.startAccessingSecurityScopedResource()
                    defer {
                        if gotAccess {
                            externalURL.stopAccessingSecurityScopedResource()
                        }
                    }
                    
                    // 2. Immediately copy to local sandbox & store the sandbox URL
                    do {
                        let localURL = try SandboxImporter.importToSandbox(from: externalURL)
                        
                        // assign LOCAL sandbox URL to var in the observable class instance so everyone can see it
                        fileContainerModel.localSandboxFileURL = localURL
                        print("Successfully ingested file to sandbox: \(localURL.path)")
                        
                    } catch {
                        print("Failed to import file to sandbox: \(error)")
                    }
                    
                case .failure(let error):
                    print("File picker error: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    @Previewable var fileContainerModel = SourceFileContainerModel()
    fileContainerModel.localSandboxFileURL = URL(fileURLWithPath: "/tmp/sample.xml") // for this to work, need to add return ; if this is deactivated, remove return from next line
    return ImportFileViewSection(fileContainerModel: fileContainerModel)
}

struct SandboxImporter {
    /// Copies or writes external file data into the app's local Documents directory.
    static func importToSandbox(from externalURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Ensure a unique local filename so existing files aren't overwritten
        let targetURL = docsDir.appendingPathComponent(externalURL.lastPathComponent)
        
        // Remove old instance if it exists at target path
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        
        // Copy the file into your app's local sandbox memory space
        try fileManager.copyItem(at: externalURL, to: targetURL)
        
        return targetURL
    }
}
