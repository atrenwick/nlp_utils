//
//  SourceContainerClass.swift
//  Tagger
//
//  Created by Adam on 10/09/2026.
//

import Foundation


@Observable
class SourceFileContainerModel {
    // to make a shared, mutable state container across multiple views -->> use Class
    var localSandboxFileURL: URL?
    
    var selectedFileName: String {
        localSandboxFileURL?.lastPathComponent ?? "No file selected"
    }
}

