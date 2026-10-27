//
//  ChildViews.swift
//  Tagger
//
//  Created by Adam on 10/09/2026.
// :: child views which get rendered in parent view :: all have ViewSection as part of name

import SwiftUI
internal import UniformTypeIdentifiers

struct BuiltSentsViewer: View {
    @Binding var myConfig: TaggerConfig
    @Binding var builtSents:[BuiltSentHolder]
    var body: some View{
        Form{
            ForEach($builtSents, id:\.self.id) { $sent in
                NavigationLink(destination: TokenisationEditView(toks: $sent.tempToks, myConfig: $myConfig)) {
                    Text(sent.toShowString(tempToks: sent.tempToks))
                }
                .contentShape(Rectangle())
                .swipeActions(edge: .trailing){
                    Button(role: .destructive){
                        builtSents.removeAll(where: {$0.id == sent.id})
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
}

struct ChooseInputFileViewSection: View {
    // for choosing the source file to get, parse
    @State private var isSelectingFile: Bool = false
    @Binding var myConfig: TaggerConfig
    
    var body: some View {
        HStack {
            Text("Source:")
            Spacer()
            Text(myConfig.inputConfig.selectedInputFile?.lastPathComponent ?? "Not Selected")
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                isSelectingFile = true
            } label: {
                Image(systemName: myConfig.inputConfig.selectedInputFile == nil ? "folder" : "arrow.triangle.2.circlepath")
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

struct ExportConfigViewSection: View {
    @State private var isSelectingFolder: Bool = false
    @State private var isProcessing: Bool = false
    @Binding var myConfig: TaggerConfig

    var xmlSettingDisplayText: String{
        switch myConfig.exportConfig.selectedExportFormat {
        case .xml:
            return "XML Settings"
        case .xmlConll:
            return "XML-CoNLL settings"
        case .conll, .conllTxt, .conllTidy:
            return "CoNLL settings"
        }
    }

    var body: some View {
        Section("Export Configuration") {
            Picker("Export (sub)type", selection: $myConfig.exportConfig.selectedExportFormat){
                ForEach(ExportFormat.allCases.sorted {$0.rawValue < $1.rawValue }){ formatOption in
                    Text(formatOption.rawValue)
                }
            }
            // 1. User types the filename
            FileNameInputViewSection(myConfig: $myConfig)
            
            // 2. User chooses the target folder
            HStack {
                Text("Destination:")
                Spacer()
                Text(myConfig.exportConfig.targetFolderURL?.lastPathComponent ?? "Not Selected")
                    .foregroundColor(.secondary)
                Button("Choose...") {
                    isSelectingFolder = true
                }
            }
            NavigationLink {
                ExportSettingsDetailView(myConfig: $myConfig)
            } label: {
                Text( xmlSettingDisplayText)
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
                        myConfig.exportConfig.targetFolderURL = url
                    }
                }
            case .failure(let error):
                print("Folder selection error: \(error.localizedDescription)")
            }
        }
    }
}

struct FileNameInputViewSection: View {
    // contains TextField for entering name of file to export
    @Binding var myConfig: TaggerConfig
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack{
            TextField("File name", text: $myConfig.exportConfig.fileName)
                .textInputAutocapitalization(TextInputAutocapitalization.never)
                .autocorrectionDisabled()
                .onChange(of: myConfig.exportConfig.fileName) { _, newValue in
                    let cleaned = myConfig.exportConfig.fileName.sanitizedFileName
                    if cleaned != newValue {
                        myConfig.exportConfig.fileName = cleaned
                    }
                }
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit {
                    isFocused = false
                }
            Text(myConfig.exportConfig.selectedExportFormat.fileExtension).foregroundStyle(.secondary)
        }
    }
    func getFullURL(in folderURL: URL) -> URL {
        // 1. Fallback to a default name if user left it blank
        let cleanName = myConfig.exportConfig.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanName.isEmpty ? "Untitled" : cleanName
        return folderURL
            .appendingPathComponent(finalName)
            .appendingPathExtension("json")
    }
}

struct InputFileViewEncapsulator: View {
    @Binding var myConfig: TaggerConfig
    @Binding var builtSents: [BuiltSentHolder]
    @Binding var tempTokens: [TempToken]
    let fileContainerModel: SourceFileContainerModel
    var body: some View{
        if myConfig.inputConfig.inputFileType == .manual {
            Section {
                NavigationLink("Manual entry…"){
                    ManualTokenisationView(
                        myConfig: $myConfig,
                        builtSents: $builtSents,
                        tempTokens: $tempTokens
                    )
                }
            }
        } else {
            Section{
                ImportFileViewSection(fileContainerModel: fileContainerModel, myConfig: $myConfig )
            }
        }
    }
}



struct OutputFileListView: View{
    let runOutputFileList: [OutputFileListHelper]
    var body: some View{
        Form{
            ForEach(runOutputFileList){listItem in
                NavigationLink(destination: FileViewerView(fileURL: listItem.url)) {
                    Text("Output : \(listItem.url.lastPathComponent)")
                }
            }
        }
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
    @Binding var pretokSentsOut: [HashableSentence]
    var body: some View{
        ScrollView{
            ForEach(pretokSentsOut, id:\.self){instance in
                Text("foo")
                ForEach(instance.tokens, id:\.self){tok in
                Text(tok)}
            }
            .onDelete(perform: removeItems)
        }
    }
    
    private func removeItems(_ offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        // 2. Filter the offsets to ensure they are actually within the current bounds.
        let validOffsets = IndexSet(offsets.filter { $0 < pretokSentsOut.count })
        // If no offsets are valid (e.g., the user swiped on a deleted cell), just bail.
        guard !validOffsets.isEmpty else { return }
        pretokSentsOut.remove(atOffsets: offsets)
    }
}

struct TokenisationEditView: View {
    @Binding var toks: [TempToken]
    @FocusState var isFocused
    @Binding var myConfig: TaggerConfig
    var insertImage: String { (myConfig.parsingConfig.insertNewTokPosition == .before) ? "arrow.turn.left.up" : "arrow.turn.left.down"}
    
    var body: some View {
        Form{
            ForEach($toks) { token in
                HStack{
                    TextField("Token", text: token.form)
                }
                .contentShape(Rectangle())
                .swipeActions(edge: .trailing){
                    Button(role: .destructive){
                        toks.removeAll(where: {$0.id == token.id})
                    } label : {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading){
                    Button{
                        insertItem( myConfig.parsingConfig.insertNewTokPosition, relativeTo: token.id)
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
        guard let index = toks.firstIndex(where: { $0.id == id }) else { return }
        let newItem = TempToken(form: "")
        let insertionIndex = (position == .before) ? index : index + 1
        toks.insert(newItem, at: insertionIndex)
    }
}
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////         VIEW ELEMENTS AND SUBPARTS       ///////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////



struct BigGoButtonReadinessView: View{
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

struct InputTypeEncapsulatorView: View{
    @Binding var myConfig: TaggerConfig
    @Binding var fileContainerModel: SourceFileContainerModel
    var body: some View{
        
        Picker("Input type", selection: $myConfig.inputConfig.inputFileType){
            ForEach(InputFileType.allCases.sorted {$0.rawValue < $1.rawValue }){fType in
                Text(fType.rawValue)}
        }
        .onChange(of: myConfig.inputConfig.inputFileType) { _, newFileType in
            switch newFileType{
            case .txt:
                myConfig.parsingConfig.runRetokeniser = true
            case .manual:
                myConfig.parsingConfig.runRetokeniser = false
            case .conll, .xml, .xmlConll:
                if myConfig.inputConfig.detectLanguage {
                    if let detectedLang = FileIngestionWorkflow.detectLangInFilename(inputURL: fileContainerModel.localSandboxFileURL) {
                        myConfig.parsingConfig.selectedLanguage = detectedLang
                    }
                }
            }
        }
    }
}

struct RunExplicitButtonView: View{
    @Binding var myConfig: TaggerConfig
    @State var outputString: String = "not yet run"
    
    var body: some View{
        if myConfig.parsingConfig.runExplicit{
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
                
                Text("Use \(myConfig.parsingConfig.selectedLanguage.displayName) \(myConfig.parsingConfig.selectedTreebank.short)")
                Text(outputString)
            }
        }
    }
}

struct TaggingProgressButton: View{
    let taggingInProgress: Bool
    let isPipelineReady: Bool
    let pipelineSummary: String
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
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

struct ToolbarLinkToOutputView: View {
    @Binding var myConfig: TaggerConfig
    @Binding var topLevelOutputList: [RunOutput]
    @Binding var builtSents: [BuiltSentHolder]
    @Binding var tempTokens: [TempToken]
    let unreadCount: Int
    let safeHeaderAttribs: XmlHeaderAttribs
    
    var body: some View{
        
        NavigationLink{
            RunOutputView(
                myConfig: $myConfig,
                runs: $topLevelOutputList,
                safeHeaderAttribs: safeHeaderAttribs,
                builtSents: $builtSents,
                tempTokens: $tempTokens,
            )
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

