//
//  Extensions.swift
//  Tagger
//
//  Created by Adam on 14/09/2026.
//

import Foundation
import SwiftUI
internal import UniformTypeIdentifiers


//MARK: string extensions


extension String {
    var isLower: Bool {
        self == self.lowercased() && self != self.uppercased()
    }

    var sanitizedFileName: String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\":<>")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = self.components(separatedBy: invalidCharacters).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Export_Output" : trimmed
    }
    var xmlEscaped: String {
        var result = self
        result = result.replacingOccurrences(of: "&", with: "&amp;")   // must be first
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        return result
    }

    var asTempToken: TempToken {
            return TempToken(form: String(self))
        }
}

//MARK: sequence extensions extensions
extension Sequence where Element == Sentence {
    /// Combines calculated properties across all structures
    func generateExportText() -> String {
        return self.map { $0.conll}.joined(separator: "\n")
    }
    func generateExportTextTidy() -> String {
        return self.map { $0.conllTidy }.joined(separator: "\n")
    }
    func generateTokCount() -> String {
        String(self.reduce(0) {$0 + $1.tokCount})
    }
    
    func generateXMLsentences() -> String{
        return self.map { $0.makeXMLsent(exportFormat: .xml, includeConllSentText: false)} .joined(separator: "\n")
    }
}

extension Sequence where Element == Token {
    /// Combines calculated properties across all structures
    func makeSentenceXML() -> String {
        return self.map { $0.asXML }.joined(separator: "\n")
    }
    func makeSentenceXMLconll() -> String {
        return self.map { $0.conllRaw }.joined(separator: "\n")
    }
}

// use collection as need to get .Count
extension Collection where Element == TempToken {
    
    func makeHashableSentFromTestToks()-> HashableSentence?{
        guard self.count > 0 else {return nil}
        var keepTokens: [String] = []
        for item in self {
            if item.form != ""{
                keepTokens.append(item.form)
            }
        }
        let returnObject = HashableSentence(id: UUID().uuidString, tokens: keepTokens, conllMetas: [])
        for x in returnObject.tokens{
            print(x)
        }
        return returnObject
    }
}

extension PipelineSettingsView {
    //MARK:  calculated properties
    var loadTotal: Int {
        if myConfig.parsingConfig.modelArchitecture == .distilbert {
            return 4
        } else {
            return 10
        }
    }

    // 1. Array of missing configuration items
    var missingReqs: [String] {
        var missing: [String] = []
        
        // Rule 1: Check input file exists in sandbox
        if fileContainerModel.localSandboxFileURL == nil && myConfig.inputConfig.inputFileType != .manual{
            missing.append("Input File")
        }
        
        let ext = fileContainerModel.localSandboxFileURL?.pathExtension ?? "nil"
        if  myConfig.inputConfig.inputFileType.allowedReadExt.contains(ext) == false  && myConfig.inputConfig.inputFileType != .manual {
            missing.append("extension-InputType Mismatch")
        }
        
        if myConfig.inputConfig.inputFileType == .manual && myConfig.inputData.builtSents.count == 0 {
            missing.append("No built sents found")
        }
        
        // Rule 2: Check custom output filename is typed
        if myConfig.exportConfig.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Output Filename")
        }
        
        // Rule 3: Check target folder (or destination setting)
        if myConfig.exportConfig.targetFolderURL == nil { // and in sandbox || has auth.
            
            missing.append("Export Directory")
        }
        
        return missing
    }
    
    // 2. Boolean check for the .disabled() modifier
    var isPipelineReady: Bool {
        return missingReqs.isEmpty
    }
    
    // 3. User-friendly warning message
    var missingReqsMessage: String {
        guard !missingReqs.isEmpty else { return "" }
        
        if missingReqs.count == 1 {
            return "Set: \(missingReqs[0])"
        } else {
            // Lists items cleanly: "Missing required settings: Input File, Output Filename, Export Directory"
            return "Missing required settings: \(missingReqs.joined(separator: ", "))"
        }
    }
    
    //MARK: instance methods
    func processSentsFromPipeline(sentResult: OnSentResult, myConfig: Binding<TaggerConfig>)   {
        
        switch sentResult.resultType {
        case .success:
            myConfig.wrappedValue.outputData.outSents.append(
                PostPipelineWorkflow.postprocessSentence(sentence: sentResult.sentence, parsedTokens: sentResult.decoded, myConfig: myConfig.wrappedValue)
            )
        default:
            myConfig.wrappedValue.outputData.outErrors.append(PostPipelineWorkflow.postprocessErrorSent(sentResult: sentResult))
            print("error handled")
        }
        if myConfig.wrappedValue.parsingConfig.runExplicit { print("awaitng mainactor line 237") }
    }
    
    func callPipelineLoader(myConfig: TaggerConfig) async throws -> PipelineHelper{
        let pipeline: PipelineHelper
        var currentStatus: String = ""
        isLoading = true
        do {
            switch myConfig.parsingConfig.modelArchitecture {
            case .distilbert:
                let loader = BERTlikePipelineLoader()
                pipeline = try await loader.loadBERTlikePipe(myConfig: myConfig) {step, message in
                    loadedCount = step
                    loadStatus = message
                }
                if myConfig.parsingConfig.runExplicit { print("bert pipeline called") }
            case .cnnBiLSTM:
                let loader = CNNBiLSTMPipelineLoader()
                pipeline = try await loader.loadCNNBiLSTMpipe(myConfig: myConfig) {step, message in
                    loadedCount = step
                    loadStatus = message
                }
                currentStatus = "loaded cnnBiLSTM"
                if myConfig.parsingConfig.runExplicit { print("loaded cnnBiLSTM") }
            }
        } catch {
            if myConfig.parsingConfig.runExplicit { print("Failed to load pipeline: \(error)")}
            currentStatus = "Error loading pipeline."
            throw PipelineError.notReadyToSendToRunner
        }
        
        if myConfig.parsingConfig.runExplicit { print(currentStatus) }
        isLoading = false
        return pipeline
        
    }

    func runTagging(
        inputFileType: InputFileType,
        maxPipelineStep: PipelineStep,
        taggingInProgress: Binding<Bool>,
        isFirstRun: Binding<Bool>
    ) {
        
        if !isFirstRun.wrappedValue {
            myConfig.runResetters()
        } else {
            isFirstRun.wrappedValue = false
        }
        // MARK: parameters, initialisations for task
        myConfig.parsingConfig.runExplicit = true
        taggingInProgress.wrappedValue = true
        myConfig.progressConfig.hasStarted = true
        let theseHeaderAttribs = XMLMakingWorkflow.makeSafeHeaderAttribs(myConfig: myConfig, fileContainerModel: fileContainerModel)
        print("Build header attribs: \(theseHeaderAttribs)")
        myConfig.outputData.safeHeaderAttribs = theseHeaderAttribs
        
        // MARK: tagging :
        Task {
            do {
                var allSentences: [HashableSentence] = []
                var pipeline: PipelineHelper
                do {
                    currentStatus = "Loading pipeline"
                    pipeline = try await callPipelineLoader(myConfig: myConfig)
                    myConfig.parsingConfig.maxWords = pipeline.maxWords
                    myConfig.outputData.safeHeaderAttribs.maxWords = String(pipeline.maxWords)
//MARK: set pipeline maxwords, seqlen
                    print("Pipelinemax_words = \(pipeline.maxWords) @ 228")
                    if let pipeline = pipeline as? SubtokenAwarePipelineHelper {
                        myConfig.outputData.safeHeaderAttribs.maxSeqLen = String(pipeline.seqLen)
                        myConfig.parsingConfig.maxSeqLen = pipeline.seqLen
                        print("maxSeqLen = \(pipeline.seqLen) @ 232")
                    }
                } catch {
                    print("Failed to load pipeline: \(error)")
                    currentStatus = "Error loading pipeline."
                    throw PipelineError.notReadyToSendToRunner
                }
                if myConfig.parsingConfig.runExplicit { print(currentStatus) }
                
                //MARK: INGEST SENTS ::
                allSentences = try SentencizationWorkflow.ingestSentences(currentStatus: currentStatus, myConfig: myConfig, pipeline: pipeline)
                guard !allSentences.isEmpty else {
                    taggingInProgress.wrappedValue = false
                    throw PipelineError.noSentencesLoaded
                }
                
                //MARK: run resentenciser on request
                if ![InputFileType.txt, InputFileType.manual].contains(myConfig.inputConfig.inputFileType) && myConfig.parsingConfig.runResentenciser{
                    currentStatus = "Resentencizing"
                    myConfig.inputData.resentencizerOutputStrings = try SentencizationWorkflow.desentenciseAndResentencise(
                        sentsToDiscard: allSentences,
                        myConfig: myConfig
                    )
                    myConfig.parsingConfig.runRetokeniser = true
                }
                
                //MARK: run retokeniser if required/requested
                if myConfig.inputConfig.inputFileType != .txt && myConfig.parsingConfig.runRetokeniser && [TokenizingMethod.nltokeniser, TokenizingMethod.trained].contains(myConfig.parsingConfig.tokenizingMethod) {
                    if myConfig.parsingConfig.runExplicit {
                        currentStatus = "retokenizing"
                        print("Retokenising")
                    }
                    allSentences = try SentencizationWorkflow.retokenisationEncapsulator(
                        myConfig: myConfig,
                        pipeline: pipeline,
                        taggingInProgress: taggingInProgress
                    )
                }
                
                // optional chunk to test build-in NL parsing, send POS, lemmas to cols 8,9
                if myConfig.parsingConfig.runExplicit{
                    currentStatus = "getting NL Tags"
                    var nlInputTexts: [String] = []
                    for sent in allSentences{
                        nlInputTexts.append(sent.tokens.joined(separator: " "))
                    }
                    for chunk in nlInputTexts{
                        let _ = getNLTags(text: chunk)
                    }
                }
                
                await MainActor.run {
                    myConfig.progressConfig.totalCount = allSentences.count
                    myConfig.progressConfig.appleProgress = Progress(totalUnitCount: Int64(max(allSentences.count, 1)))
                    myConfig.progressConfig.startTime = Date()
                }
                
                // MARK: Step 2: pass prepared data to parsing pipeline
#if DEBUG
                if runfive {
                    allSentences = allSentences.count > 5 ? Array(allSentences.prefix(5)) : allSentences}
#endif
                for sentence in allSentences {
                    if myConfig.parsingConfig.runExplicit { print("processing line 232") }
                    currentStatus = "Ready to tag"
                    
                    let sentResult = pipeline.runOnSentence(sentence, myConfig: myConfig)
                    processSentsFromPipeline(sentResult: sentResult, myConfig: $myConfig )
                                             
                    await MainActor.run {
                        myConfig.progressConfig.processedCount += 1
                        myConfig.progressConfig.appleProgress.completedUnitCount = Int64(myConfig.progressConfig.processedCount)
                    }
                }
//MARK: print
                try PrintWorkflow.dumpDetailsForRunExplicit(myConfig: myConfig, taggingInProgress: $taggingInProgress)
                runOutput = PostPipelineWorkflow.makeTidyRunOutput(myConfig: myConfig)
                
                try await MainActor.run {
                    taggingInProgress.wrappedValue = false
                    currentStatus = "Done"
                    guard let runOutput else { throw PipelineError.noRunOutput }
                    topLevelOutputList.append(runOutput)
                    if myConfig.parsingConfig.runExplicit{
                        print("topLevelOutputList length == \(topLevelOutputList.count)")
                    }
                }
            } catch {
                switch error {
                case let PipelineError as PipelineError:
                    myConfig.progressConfig.alertMessage = PipelineError.errorDescription
                case let nsError as NSError where nsError.domain == XMLParser.errorDomain:
                    myConfig.progressConfig.alertMessage = "XML Parsing error : No valid XML to parse"
                default:
                    myConfig.progressConfig.alertMessage = error.localizedDescription
                }
                await MainActor.run {
                    taggingInProgress.wrappedValue = false
                }
            }
        }
    }

}
