//
//  AppModelClass.swift
//  Tagger
//
//  Created by Adam on 11/11/2026.
//
import Foundation
import Combine

@Observable
class AppModel {
    var currentMode: ParsingType = .single
    var myConfig = TaggerConfig()
    var allRunOutputs: [RunOutput] = []
    var runOutput: RunOutput?
    var builtSents: [BuiltSentHolder] = []
    var tempTokens: [TempToken] = []
    var toks: [TempToken] = []
    var fileContainerModel:SourceFileContainerModel = SourceFileContainerModel()
    var pretokSentsOut: [HashableSentence] = []
    var requestedOffset: Int = 0
    var usePreviousRun: Bool = false
    var safeHeaderAttribs: XmlHeaderAttribs = XmlHeaderAttribs()
    var runOutputFileList: [OutputFileListHelper] = []
    var outputLines: [String] = []
    var outSents: [Sentence] = []
    var outErrors: [OutputError] = []
    @ObservationIgnored
    let pipelineCache = PipelineCache()
    
    func runResetters(){
        builtSents = []
        tempTokens = []
        toks = []
        pretokSentsOut = []
        outputLines = []
    }
}

/// cache object to hold the currently loaded pipeline and allow verification of change
@MainActor
final class PipelineCache: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    @Published var isLive: Bool = false
    var key: PipelineKey?
    private var pipeline: (any PipelineHelper)?

    func lookup(_ newKey: String) -> (any PipelineHelper)? {
        if let pipeline, key == newKey { return pipeline }   // reuse
        pipeline = nil
        key = nil                            // else release the old one FIRST
        isLive = false
        return nil
    }
    func store(_ newPipeline: any PipelineHelper, key newKey: String) {
        print("running store function")
        pipeline = newPipeline
        key = newKey
        isLive = true
        print("live status inside func == \(isLive)")
    }
    func evict() { pipeline = nil; key = nil }
    init(){}
}

/// class for interacting with the sandbox
@Observable
class SourceFileContainerModel {
    // to make a shared, mutable state container across multiple views -->> use Class
    var localSandboxFileURL: URL?
    var selectedFileName: String { localSandboxFileURL?.lastPathComponent ?? "No file selected" }
}

