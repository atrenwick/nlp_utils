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
    let inputFileType: InputFileType
    var body: some View {
        HStack(spacing: 16) {
            if let localURL = fileContainerModel.localSandboxFileURL {
                HStack{
                    Text(localURL.lastPathComponent)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            
            Button {
                isSelectingFile = true
            } label: {
                if fileContainerModel.localSandboxFileURL == nil {
                    Text("Select Input File")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .fileImporter(
                isPresented: $isSelectingFile,
                allowedContentTypes: [.item],//inputFileType.utType, // Accepts any file type
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
                    
                    // copy to local sandbox, store sandbox URL
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
    @Previewable var inputFileType: InputFileType = .conll
    @Previewable var fileContainerModel = SourceFileContainerModel()
    fileContainerModel.localSandboxFileURL = URL(fileURLWithPath: "/tmp/sample.xml") // for this to work, need to add return ; if this is deactivated, remove return from next line
    return ImportFileViewSection(fileContainerModel: fileContainerModel, inputFileType: inputFileType)
}

