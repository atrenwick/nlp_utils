//
//  RunOutputDetailView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI


struct RunOutputDetailView: View{
    @Environment(\.openURL) var openURL
    @Environment(AppModel.self) internal var model
    
    @Binding var run: RunOutput
    @State var hasAppeared: Bool = false
    @State var fileToView: URL? =   nil
    @State var alertMessage: String?
    @State var additionalExportFormat: ExportFormat = .conll
    @State var sentDictOutput: Dictionary<String,[String:ConsolidatedToken]> = [:]
    @State var outputString: String?
    @State var savedURL: URL?
    var exportFormatShowCases: [ExportFormat]{
        ExportFormat.allCases.filter { format in
            format != model.myConfig.exportConfig.selectedExportFormat
        }
    }
    
    var body: some View {
        NavigationStack{
            Form{
                Section("Run \(run.asShortUUID)"){
                    if model.myConfig.inputConfig.inputFileType == .manual{
                        NavigationLink(destination: BuiltSentsViewer()
                        ){
                            Text("Input sents")
                        }
                    } else {
                        NavigationLink(destination: FileViewerView(fileURL: run.runMetas.sourceFileURL)) {
                            Text("Input file : \(run.runMetas.sourceFileName)")
                        }
                    }
                    //inspect output file/s
                    if model.runOutputFileList.count == 1 {
                        NavigationLink(destination: FileViewerView(fileURL: fileToView)) {
                            Text("Output : \(run.runMetas.outputFileName)")
                        }
                    } else {
                        NavigationLink(destination: OutputFileListView()){
                            Text("Output files")
                        }
                    }
                    NavigationLink(destination: RunErrorSummaryView(myConfig: model.myConfig, toksIn: run.runData.tokCount)){
                        Text("Coverage :: \(model.myConfig.outputData.outErrors.count) errors")}
                    Text("Sentence count : \(run.runData.sents.count)")
                    Text("Tok count : \(run.runData.tokCount)")
                    Text("Language : \(run.runMetas.lang)")
                    Text("Treebank : \(run.runMetas.treebank)")
                }
                Section("Additional Export"){
                    HStack{
                        Picker("Format", selection: $additionalExportFormat) {
                            ForEach(exportFormatShowCases) { format in
                                Text(format.rawValue)
                            }
                        }
                        Spacer()
                        AdditionalExportButtonView( additionalExportFormat: $additionalExportFormat, alertMessage: $alertMessage, run: run)
                    }
                }
                Section("Dictionary"){
                    HStack{
                        Text("make dict")
                        Spacer()
                        Button {
                            do {
                                savedURL = try runXMLWriter()
                            } catch {
                                error
                                print("Error caught @ 180")
                            }
                        } label : {
                            Text("ExportConsolidated")
                        }
                    }.buttonStyle(.borderedProminent)
                }
            }
            .toolbar{
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarSaveButtonView(run: run, alertMessage: $alertMessage)
                }
            }
            .onAppear{
                if hasAppeared == false{
                    hasAppeared = true
                    if let hasURL = run.runMetas.savedURL{
                        model.runOutputFileList.append(
                            OutputFileListHelper(
                                id: UUID(),
                                runID: run.runMetas.runID,
                                url: hasURL
                            )
                        )
                        fileToView = hasURL
                    }
                }
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: {alertMessage != nil},
                set: {if !$0 {alertMessage = nil}}
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            run.runMetas.unread = false
        }
    }
    
    func runXMLWriter()  throws -> URL? {
        @Bindable var model = model
        guard let folderURL = model.myConfig.exportConfig.targetFolderURL else {
            if model.myConfig.parsingConfig.verbosity.rawValue > 1{ print("Guard 661 fail")
            }
            throw PipelineError.ExportError.outputFolderCreationError
        }
        outputString = makeSentDictionary(runs: model.allRunOutputs, safeHeaderAttribs: run.runMetas.safeHeaderAttribs, processingStatus: run.runMetas.processingStatus)
        guard let outputString else {
            savedURL = nil
            throw PipelineError.ExportError.makeExportContentError
        }
        savedURL = try PipelineServices.ExporterService.exportDataToFile(
            exportContent: outputString,
            customName: run.runID,
            targetFolderURL: model.myConfig.exportConfig.targetFolderURL!,
            exportFormat: .xml,
            verbosity: .level2
        )
        if let savedURL = savedURL{
            return savedURL
        } else {
            return nil
        }
    }
    
    func makeSentDictionary(runs: [RunOutput], safeHeaderAttribs: XmlHeaderAttribs,processingStatus: ProcessingStatus )-> String {
        var currentSentID: String = ""
        var toksInCurrentSent: Dictionary<String,ConsolidatedToken> = [:]
        var sentToTokDict: Dictionary<String,[String:ConsolidatedToken]> = [:]
        var currentToken: ConsolidatedToken
//        var stringStorage: [String] = []
        var currentTokID: String
        for run in runs{
            for sent in run.runData.sents{
                currentSentID = sent.sentID
                if sentToTokDict.keys.contains(currentSentID){
                    toksInCurrentSent = sentToTokDict[currentSentID]!
                } else {
                    toksInCurrentSent = [:]
                    
                }
                for token in sent.conllData{
                    currentTokID = token.unwrappedUUID
                    if toksInCurrentSent.keys.contains(currentTokID){
                        currentToken = toksInCurrentSent[currentTokID]!
                    } else {
                        currentToken = ConsolidatedToken(
                            tokid: token.tokid,
                            tokUUID: token.unwrappedUUID,
                            form: token.form,
                            posData: [],
                            lemmaData: [],
                            featsData: [],
                            headData: [],
                            deprelData: []
                        )
                    }
                    let runDesc = [run.runMetas.safeHeaderAttribs.modelArchitecture, run.runMetas.lang, run.runMetas.treebank].joined(separator: "_")
                    currentToken.posData.append(
                        ConsolidatedAnnotationData(source: "\(runDesc)_pos", value: token.upos == "_" ? token.xpos : token.upos)
                    )
                    currentToken.lemmaData.append(
                        ConsolidatedAnnotationData(source: "\(runDesc)_lemma", value: token.lemma)
                    )
                    currentToken.featsData.append(
                        ConsolidatedAnnotationData(source: "\(runDesc)_feats", value: token.feats)
                    )
                    currentToken.headData.append(
                        ConsolidatedAnnotationData(source: "\(runDesc)_head", value: token.head)
                    )
                    currentToken.deprelData.append(
                        ConsolidatedAnnotationData(source: "\(runDesc)_deprel", value: token.deprel)
                    )
                    toksInCurrentSent[currentTokID] = currentToken
                }
                sentToTokDict[currentSentID] = toksInCurrentSent
            }
        }
        var myStringDump: [String] = []
        var sentNum: Int = 0
        var tokNum: Int = 0
        for key in sentToTokDict.keys{
            sentNum += 1
            myStringDump.append("<s id = \"\(key.xmlEscaped)\" num=\"\(sentNum)\">\n")
            let blob = sentToTokDict[key]!
            let str = blob.values
                .sorted {$0.tokid < $1.tokid}
                .map { $0.asXML}
                .joined(separator: "\n")
            myStringDump.append(str)
            myStringDump.append("\n</s>\n\n")
            tokNum += blob.values.count
        }
        
        let xmlHeader = XMLMakingWorkflow.makeSentDictionaryHeader(
            sentNum: sentNum,
            tokNum: tokNum,
            safeHeaderAttribs: safeHeaderAttribs,
            processingStatus: processingStatus
        )
        
        let xmlFooter = """
        </p>
        </body>
        </text>
        </TEI.2>
        """
        let outputString = [xmlHeader, myStringDump.joined(separator: "\n"), xmlFooter].joined(separator: "\n")
        return outputString
    }
}

