//
//  ChildViews.swift
//  Tagger
//
//  Created by Adam on 10/09/2026.
// :: child views which get rendered in parent view :: all have ViewSection as part of name

import SwiftUI
internal import UniformTypeIdentifiers

///look at built sentences
struct BuiltSentsViewer: View {
    @Environment(AppModel.self) private var model
    @State var showClearAllButton: Bool = false
    var body: some View{
        @Bindable var model = model
        Form{
            ForEach($model.builtSents, id:\.self.id) { $sent in
                NavigationLink(destination: TokenisationEditView()) {
                    Text(sent.toShowString(tempToks: sent.tempToks))
                }
                .contentShape(Rectangle())
                .swipeActions(edge: .trailing){
                    Button(role: .destructive){
                        model.builtSents.removeAll(where: {$0.id == sent.id})
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .toolbar{
            if model.builtSents.count > 0 {
                ToolbarItem(placement: .topBarTrailing){
                    Button{
                        showClearAllButton = true
                    } label: {
                        Text("Clear all")
                    }
                }
            }
        }
        .confirmationDialog("Clear all" , isPresented: $showClearAllButton, titleVisibility: .visible){
            Button("Clear all", role: .destructive){
                model.builtSents = []
            }
            Button("Cancel", role: .cancel){ }
        } message: {
            Text("Clear all built sents")
        }
    }
}

/// Choose the source file to get, parse
struct ChooseInputFileViewSection: View {
    @Environment(AppModel.self) private var model
    @State private var isSelectingFile: Bool = false
    
    var body: some View {
        @Bindable var model = model
        HStack {
            Text("Source:")
            Spacer()
            Text(model.myConfig.inputConfig.selectedInputFile?.lastPathComponent ?? "Not Selected")
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                isSelectingFile = true
            } label: {
                Image(systemName: model.myConfig.inputConfig.selectedInputFile == nil ? "folder" : "arrow.triangle.2.circlepath")
            }
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
                        let _ = try String(contentsOf: url, encoding: .utf8)
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
///choose where to export files
struct ExportConfigViewSection: View {
    @Environment(AppModel.self) private var model
    @State private var isSelectingFolder: Bool = false
    @State private var isProcessing: Bool = false

    var xmlSettingDisplayText: String{
        switch model.myConfig.exportConfig.selectedExportFormat {
        case .xml:
            return "XML Settings"
        case .xmlConll:
            return "XML-CoNLL settings"
        case .conll, .conllTxt, .conllTidy:
            return "CoNLL settings"
        }
    }
    
    var body: some View {
        @Bindable var model = model
        Section("Export Configuration") {
            Picker("Export (sub)type", selection: $model.myConfig.exportConfig.selectedExportFormat){
                ForEach(ExportFormat.allCases.sorted {$0.rawValue < $1.rawValue }){ formatOption in
                    Text(formatOption.rawValue)
                }
            }
            // 1. User types the filename
            FileNameInputViewSection()
            
            // 2. User chooses the target folder
            HStack {
                Text("Destination:")
                Spacer()
                Text(model.myConfig.exportConfig.targetFolderURL?.lastPathComponent ?? "Not Selected")
                    .foregroundColor(.secondary)
                Button("Choose...") {
                    isSelectingFolder = true
                }
            }.contentShape(Rectangle())
                .swipeActions(edge: .leading){
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    HStack{
                        Button(role: .confirm){
                            setOutputDirTo(.defaultvalue)
                            generator.impactOccurred()
                        } label: {
                            VStack{
                                Text("Default")
                                    .foregroundStyle(.primary)
                                Image(systemName: "house.fill")
                            }
                            .tint(.blue)
                        }
                        Button(role: .confirm){
                            setOutputDirTo(.sandbox)
                            generator.impactOccurred()
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "iphone")
                                    .font(.body)
                                Text("Sandbox")
                                    .font(.caption)
                            }
                        }.tint(.green)
                    }
                }
            NavigationLink {
                ExportSettingsDetailView()
            } label: {
                Text(xmlSettingDisplayText)
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
                        model.myConfig.exportConfig.targetFolderURL = url
                    }
                }
            case .failure(let error):
                print("Folder selection error: \(error.localizedDescription)")
            }
        }
    }
    private func setOutputDirTo(_ dir: ResetDirOption) {
        // Re-assign default bookmark URL back to the config instance
        switch dir {
        case .defaultvalue:
                model.myConfig.exportConfig.targetFolderURL = PipelineServices.ExporterService.resolveDefaultBookmark()
        case .sandbox:
                model.myConfig.exportConfig.targetFolderURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
    }
}
//#Preview {
//    @Previewable @State var myConfig: TaggerConfig = TaggerConfig()
//    ExportConfigViewSection(myConfig: $myConfig)
//}

/// set name of file to export
struct FileNameInputViewSection: View {
    // contains TextField for entering name of file to export
    @Environment(AppModel.self) private var model
    @FocusState private var isFocused: Bool
    
    var body: some View {
        @Bindable var model = model
        HStack{
            TextField("File name", text: $model.myConfig.exportConfig.fileName)
                .textInputAutocapitalization(TextInputAutocapitalization.never)
                .autocorrectionDisabled()
                .onChange(of: model.myConfig.exportConfig.fileName) { _, newValue in
                    let cleaned = model.myConfig.exportConfig.fileName.sanitizedFileName
                    if cleaned != newValue {
                        model.myConfig.exportConfig.fileName = cleaned
                    }
                }
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit {
                    isFocused = false
                }
            Text(model.myConfig.exportConfig.selectedExportFormat.fileExtension).foregroundStyle(.secondary)
        }
    }
    func getFullURL(in folderURL: URL) -> URL {
        @Bindable var model = model
        // 1. Fallback to a default name if user left it blank
        let cleanName = model.myConfig.exportConfig.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanName.isEmpty ? "Untitled" : cleanName
        return folderURL
            .appendingPathComponent(finalName)
            .appendingPathExtension("json")
    }
}

///BigGoButtonReadinessExtractedView is the alert section that appears based on `missingReqsMessage` which is a calculated property
struct GoSectionUpperHalf: View{
    @Binding var currentStatus: String
    @Binding var isLoading: Bool
    @Binding var loadedCount: Int
    @Binding var loadStatus: String
    @Binding var myConfig: TaggerConfig
    
    let isPipelineReady: Bool
    let loadTotal: Int
    let missingReqsMessage: String
    
    var body: some View {
        /// this has calculated property auto-hiding, showing, based on config ; same value (de)activates the button, in its own view
        BigGoButtonReadinessExtractedView(
            isPipelineReady: isPipelineReady,
            missingReqsMessage: missingReqsMessage
        )
        if myConfig.viewSettings.showLoadProgress  {
            Text("part2")
            VStack {
                ProgressView(
                    value: isLoading ? Double(loadedCount) : 0.0,
                    total: Double(loadTotal)
                )
                HStack{
                    Text(loadStatus)
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
        }
        if myConfig.viewSettings.showProcessingProgress {
            PipelineProgressView(myConfig: $myConfig, currentStatus: $currentStatus).id("processingProgressView")
        }
    }
}

/// view for choosing input file type
struct InputFileViewEncapsulator: View {
    @Environment(AppModel.self) private var model

    var linkDisplayString: String {
        model.builtSents.count > 0 ? "Manual entry:             \(model.builtSents.count) sents" : "Manual entry…"
    }
    var body: some View{
         @Bindable var model = model
        if model.myConfig.inputConfig.inputFileType == .manual {
            Section {
                NavigationLink(linkDisplayString){
                    ManualTokenisationView()
                }
            }
        } else {
            Section{
                ImportFileViewSection(fileContainerModel: model.fileContainerModel, myConfig: $model.myConfig )
            }
        }
    }
}

///list of output files
struct OutputFileListView: View{
     @Environment(AppModel.self) private var model

    var body: some View{
        Form{
            ForEach(model.runOutputFileList){listItem in
                NavigationLink(destination: FileViewerView(fileURL: listItem.url)) {
                    Text("Output : \(listItem.url.lastPathComponent)")
                }
            }
        }
    }
}

/// list of output lines
struct OutputLinesExtractedView: View {
    @Environment(AppModel.self) private var model

    private var visibleSents: [String] {
        Array(model.outputLines.prefix(50))
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

/// View for looking at pretokenized sentences
struct PretokenisedSentExtractedView : View {
     @Environment(AppModel.self) private var model
    var body: some View{
        ScrollView{
            ForEach(model.pretokSentsOut, id:\.self){instance in
                Text("foo")
                ForEach(instance.tokens, id:\.self){tok in
                Text(tok)}
            }
            .onDelete(perform: removeItems)
        }
    }
    
    private func removeItems(_ offsets: IndexSet) {
        @Bindable var model = model
        guard !offsets.isEmpty else { return }
        // 2. Filter the offsets to ensure they are actually within the current bounds.
        let validOffsets = IndexSet(offsets.filter { $0 < model.pretokSentsOut.count })
        // If no offsets are valid (e.g., the user swiped on a deleted cell), just bail.
        guard !validOffsets.isEmpty else { return }
        model.pretokSentsOut.remove(atOffsets: offsets)
    }
}

/// View to edit tokenisation with form
struct TokenisationEditView: View {
    @Environment(AppModel.self) private var model
    @FocusState var isFocused
    var insertImage: String { (model.myConfig.parsingConfig.insertNewTokPosition == .before) ? "arrow.turn.left.up" : "arrow.turn.left.down"}
    
    var body: some View {
        @Bindable var model = model
        Form{
            ForEach($model.toks) { token in
                HStack{
                    TextField("Token", text: token.form)
                }
                .contentShape(Rectangle())
                .swipeActions(edge: .trailing){
                    Button(role: .destructive){
                        model.toks.removeAll(where: {$0.id == token.id})
                    } label : {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading){
                    Button{
                        insertItem( model.myConfig.parsingConfig.insertNewTokPosition, relativeTo: token.id)
                    } label: {
                        VStack{
                            Image(systemName: insertImage)
                        }
                    }
                }
                .textInputAutocapitalization(TextInputAutocapitalization.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.go)
                .onSubmit {
                    isFocused = false
                }
            }
        }
    }
    
    func insertItem(_ position: InsertPosition, relativeTo id: UUID){
        @Bindable var model = model
        guard let index = model.toks.firstIndex(where: { $0.id == id }) else { return }
        let newItem = TempToken(form: "")
        let insertionIndex = (position == .before) ? index : index + 1
        model.toks.insert(newItem, at: insertionIndex)
    }
}
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////         VIEW ELEMENTS AND SUBPARTS       ///////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

///Show the not-ready warning messages
struct BigGoButtonReadinessExtractedView: View{
    let isPipelineReady: Bool
    let missingReqsMessage: String
    var body: some View{
            if !isPipelineReady {
                VStack{
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(missingReqsMessage)
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

/// Picker for input types and its onChange modifiers
struct InputTypeExtractedView: View{
    @Environment(AppModel.self) private var model

    var body: some View{
        @Bindable var model = model
        
        Picker("Input type", selection: $model.myConfig.inputConfig.inputFileType){
            ForEach(InputFileType.allCases.sorted {$0.rawValue < $1.rawValue }){fType in
                Text(fType.rawValue)}
        }
        .onChange(of: model.myConfig.inputConfig.inputFileType) { _, newFileType in
            switch newFileType{
            case .txt:
                    model.myConfig.parsingConfig.runRetokeniser = true
            case .manual:
                    model.myConfig.parsingConfig.runRetokeniser = false
            case .conll, .xml, .xmlConll:
                    if model.myConfig.inputConfig.detectLanguage {
                        if let detectedLang = FileIngestionWorkflow.detectLangInFilename(
                            inputURL: model.fileContainerModel.localSandboxFileURL) {
                            model.myConfig.parsingConfig.selectedLanguage = detectedLang
                    }
                }
            }
        }
    }
}

///View for set of buttons to run test load functions
struct RunExplicitButtonExtractedView: View{
    @Environment(AppModel.self) private var model
    @State var outputString: String = "not yet run"
    
    var body: some View{
        if model.myConfig.parsingConfig.runExplicit{
            HStack{
                Button {
                    //                    outputString = testInstantiatePipeline(myConfig: myConfig)
                } label: {
                    Text("Test load")
                }
                .tint(.orange)
                .buttonStyle(.borderedProminent)
                
                Button {
                    outputString = "reset"
                } label: {
                    Text("reset")
                }
                .tint(.blue)
                .buttonStyle(.borderedProminent)
                
                Text("Use \(model.myConfig.parsingConfig.selectedLanguage.displayName) \(model.myConfig.parsingConfig.selectedTreebank.short)")
                Text(outputString)
            }
        }
    }
}

/// View to specify where to start processing sents : @ sent0, 1, 2…
struct TaggingOffsetParamsView: View{
    @Environment(AppModel.self) private var model
    /// is there a previous run which might be able to be resumed
    var previousRun: [RunOutput] {
        if model.allRunOutputs.count == 0 {
            return []
        } else if model.allRunOutputs.count == 1 {
            return model.allRunOutputs
        } else {
            let sorted = model.allRunOutputs.sorted {$0.runMetas.safeHeaderAttribs.taggingDate < $1.runMetas.safeHeaderAttribs.taggingDate}
            if let mostRecent = sorted.last{
                return [mostRecent]
            } else {
                return []
            }
        }
    }
    /// determine if a previous run that does exist is actually resumable
    var previousResumable: Bool{
        if previousRun.count >= 1  && previousRun[0].runMetas.processingStatus.interruptRequested == "True" {
            return true
        } else {
            return false
        }
    }
    
    var body: some View{
        @Bindable var model = model
        Form {
            Toggle(isOn: $model.usePreviousRun) {
                Text("Restart last interrupted")
            }
            .onChange(of: model.usePreviousRun){_, newValue in
                if newValue == true && previousResumable {
                    model.requestedOffset = previousRun[0].runMetas.processedCount
                }
            }
            .disabled(previousResumable == false)
            
            HStack{Text("Start from sentence…")
                TextField("Add sent number", value: $model.requestedOffset, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
            }
        }
    }
}

/// visual of the button to push to run the pipeline
struct TaggingProgressButtonExtractedView: View{
    @Environment(AppModel.self) private var model

    let taggingInProgress: Bool
    let isPipelineReady: Bool
    let pipelineSummary: String
    @Binding var currentPipelineDesc: PipelineDesc?
    @Binding var currentPipelineLoaded: Bool
    var previous: Int = 0
    var body: some View {
        Group {
            VStack {
                HStack {
                    Image(systemName: taggingInProgress ? "progress.indicator" : "play.fill")
                        .symbolEffect(.rotate, options: .repeating, isActive: taggingInProgress)
                    Text(taggingInProgress ? "Running" : "Run")
                        .fontWeight(.semibold)
                }
                if currentPipelineLoaded, let loadedDesc = currentPipelineDesc {
                    HStack{
                        Text(loadedDesc.lang.uppercased())
                        Spacer()
                        Text(loadedDesc.tb)
                        Spacer()
                        Text(loadedDesc.llm)
                        Spacer()
                        Text(loadedDesc.tok)
                    }
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

/// Navigation link + image to RunOutput view
struct ToolbarLinkToOutputExtractedView: View {
    @Environment(AppModel.self) private var model
    var unreadCount: Int = 0
    
    var body: some View{
        
        NavigationLink{
            RunOutputView()
        } label: {
            Image(systemName: "book.pages.fill")
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        Text(String(unreadCount))
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(.red))
                            .offset(x: 8, y: -8)
                    }
                }
        }
    }
}
