//
//  FileViewerView.swift
//  Tagger
//
//  Created by Adam on 20/09/2026.
//

import SwiftUI
import QuickLook

// MARK: - FileViewerView
struct FileViewerView: View{
//
// wrapper screen that hosts a QuickLook preview of a file.
// NavigationLink pushes to this view
// QuickLookPreview does the actual UIKit bridging.
//
    let fileURL: URL?
    
    var body: some View{
        if let url = fileURL{
            QuickLookPreview(url: url)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            Text("File not found")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - QuickLookPreview
struct QuickLookPreview: UIViewControllerRepresentable {
    // The file QuickLook should display. Must be a valid, readable file URL.
    let url: URL
    
    
    // We create a QLPreviewController and point its dataSource at our Coordinator
    func makeUIViewController(context: Context) ->  QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
        
    }
    // this method is a required part of
    // the UIViewControllerRepresentable protocol.
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    // Create Coordinator that will act as QLPreviewController's dataSource.
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    // MARK: Coordinator - Acts as the "bridge object" required by UIKit's delegate/dataSource pattern.
    class Coordinator: NSObject, QLPreviewControllerDataSource{
        let url: URL
        init(url: URL) {self.url = url}

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem{
            url as NSURL
        }
    }
    
}
