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
//
// A SwiftUI bridge ("wrapper") around UIKit's QLPreviewController, which is Apple's
// built-in, system-wide file preview UI — the same viewer used by Mail, Files, and
// Messages for attachments. It supports a wide range of file types out of the box
// (PDF, images, plain text, code, spreadsheets, etc.) with pinch-zoom, sharing, and
// markup, without us having to write any custom rendering code per file type.
//
// SwiftUI has no native "preview this file" view, so we implement the
// UIViewControllerRepresentable protocol to drop a UIKit view controller
// (QLPreviewController) into a SwiftUI view hierarchy.
struct QuickLookPreview: UIViewControllerRepresentable {
    // The file QuickLook should display. Must be a valid, readable file URL.
    let url: URL
    
    
    // Called once by SwiftUI to create the underlying UIKit view controller.
    // We create a QLPreviewController and point its dataSource at our Coordinator
    // (below), since QLPreviewController pulls its content via a delegate/dataSource
    // pattern rather than being handed the file directly.
    func makeUIViewController(context: Context) ->  QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
        
    }
    // Called by SwiftUI whenever this view's inputs change and the view controller
    // needs to be updated to match. We have nothing to update here since the URL
    // is fixed for the lifetime of this view, but the method is a required part of
    // the UIViewControllerRepresentable protocol.
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    // Creates the Coordinator that will act as QLPreviewController's dataSource.
    // SwiftUI calls this automatically and keeps the Coordinator alive for as long
    // as this view exists, which is what lets it safely act as a delegate/dataSource
    // (UIKit delegates are typically reference types with a defined lifetime — a
    // SwiftUI struct alone can't fill that role directly).
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    // MARK: Coordinator
    //
    // Acts as the "bridge object" required by UIKit's delegate/dataSource pattern.
    // QLPreviewController doesn't take a file directly — it asks its dataSource,
    // at preview time, "how many items do you have?" and "give me item N" — so this
    // Coordinator's job is simply to answer those two questions with our one file.
    class Coordinator: NSObject, QLPreviewControllerDataSource{
        let url: URL
        init(url: URL) {self.url = url}


        // QLPreviewController calls this first to find out how many files to show
        // (it supports multi-file previews with paging; we only ever show one).
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        
        // QLPreviewController calls this to fetch each item it needs to display,
        // by index. QLPreviewItem is a protocol; NSURL already conforms to it,
        // so we can hand our file URL straight back without extra wrapping.
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem{
            url as NSURL
        }
    }
    
}
