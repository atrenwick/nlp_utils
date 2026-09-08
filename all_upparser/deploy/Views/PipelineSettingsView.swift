//
//  PipelineSettingsView.swift
//  Tagger
//
//  Created by Adam on 08/09/2026.
//
//TODO: A-B choices for tokenisation method, source type, sourcelang
//TODO: output conll : change to std, grid ; std needs to have \t
//TODO: parse from file rather than bundle
//TODO: export, share parsed output

import SwiftUI
internal import UniformTypeIdentifiers

enum InputFileType: String, Identifiable, CaseIterable {
    case conll
    case txt
    case xml
    
    var id: Self { self }

    var isTokenised: Bool {
        switch self {
        case .conll: return true
        case .txt: return false
        case .xml: return true
        }
    }
}


struct PipelineSettingsView: View {
    @State private var fileName: String = ""
    @State private var targetFolderURL: URL? = nil
    @State private var selectedOutputPlaform: OutputTarget = .ViewOnly

    @State private var selectedLanguage: Language = .EN
    @State private var selectedModel: Language.Model = .enModel1
    @State var maxPipelineStep: PipelineStep? = .step1
    @State var inputFileType: InputFileType = .conll

    var body: some View {
        
        
        
        NavigationStack{
            Form {
                
                // First Picker
                Section("Parameters"){
                    Picker("Inputtype", selection: $inputFileType){
                        ForEach(InputFileType.allCases){fType in
                            Text(fType.rawValue)}
                    }
                    
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(Language.allCases) { lang in
                            Text(lang.rawValue) // Displays "EN", "FR"
                        }
                    }
                    .onChange(of: selectedLanguage) { _, newLang in
                        if let first = newLang.availableModels.first {
                            selectedModel = first
                        }
                    }
                    // Model picker, dynamically updating based on Lang picker
                    Picker("Model", selection: $selectedModel) {
                        ForEach(selectedLanguage.availableModels) { model in
                            Text(model.rawValue)
                        }
                    }
                    NavigationLink("Select processor steps"){
                        ProcessorStepConfigView(maxActiveStep: $maxPipelineStep, inputFileType: $inputFileType)
                    }
                }
                ExportConfigView(fileName: $fileName, targetFolderURL: $targetFolderURL, selectedOutputPlaform: $selectedOutputPlaform)
                
            }
        }
    }
}

#Preview {
    PipelineSettingsView()
}

// choose languages supported ::: LanguageCode enum
// choose from one of languages for which there is a model



// enum : is conll output for this app or somwehere else: controls CoNLL space formatting : use raw wtih \t, cf tidy with n spaces
enum OutputTarget: String, CaseIterable, Identifiable{
    var id: Self {self}
    case Export
    case ViewOnly
}

enum Language: String, CaseIterable, Identifiable {
    case EN
    case FR
    case DE

    var id: Self { self }

    // Readable label for the first picker
    var displayName: String {
        switch self {
        case .EN: return "en"
        case .FR: return "fr"
        case .DE: return "de"
        }
    }

    // Nested enum for all available models
    enum Model: String, CaseIterable, Identifiable {
        case enModel1 = "en_ewt"
        case enModel2 = "en_gum"
        case frModel1 = "fr_gsd"
        case frModel2 = "fr_sequoia"
        case deModel1 = "de_gsd"

        var id: String { rawValue }
    }

    // Returns ONLY the models valid for this language
    var availableModels: [Model] {
        switch self {
        case .EN: return [.enModel1, .enModel2]
        case .FR:  return [.frModel1, .frModel2]
        case .DE:  return [.deModel1]
        }
    }
}

struct SanitizedFileNameInputView: View {
    @Binding var fileName: String
    
    // Set of characters prohibited in file names across major file systems
    private let invalidFileNameCharacters: CharacterSet = {
        var invalid = CharacterSet(charactersIn: #"/:\*?"<>|"#)
        invalid.formUnion(.controlCharacters)
        invalid.formUnion(.newlines)
        return invalid
    }()
    
    var body: some View {
//        Form {
//            Section(header: Text("Export File Name")) {
                
        HStack{
            TextField("File name", text: $fileName)
                        .onChange(of: fileName) { _, newValue in
                            // Strip any forbidden characters immediately as typed or pasted
                            let cleaned = newValue.components(separatedBy: invalidFileNameCharacters).joined()
                            if cleaned != newValue {
                                fileName = cleaned
                            }
                        }
            Text(".conll").foregroundStyle(.secondary)
        }
        
//        }
    }
    func getFullURL(in folderURL: URL) -> URL {
        // 1. Fallback to a default name if user left it blank
        let cleanName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanName.isEmpty ? "Untitled" : cleanName
        
        // 2. Append the extension (e.g., .json or .txt)
        return folderURL
            .appendingPathComponent(finalName)
            .appendingPathExtension("json")
    }

}

struct ExportConfigView: View {
    @State private var isSelectingFolder: Bool = false
    @State private var isProcessing: Bool = false
    
    @Binding var fileName: String
    @Binding var targetFolderURL: URL?
    @Binding var selectedOutputPlaform: OutputTarget

    var body: some View {
//        Form {
            Section("Export Configuration") {
                // 1. User types the filename
                SanitizedFileNameInputView(fileName: $fileName)
                
                
                // 2. User chooses the target folder
                HStack {
                    Text("Destination:")
                    Spacer()
                    Text(targetFolderURL?.lastPathComponent ?? "Not Selected")
                        .foregroundColor(.secondary)
                    Button("Choose...") {
                        isSelectingFolder = true
                    }
                }
                Picker("Output for…", selection: $selectedOutputPlaform) {
                    ForEach(OutputTarget.allCases) { outputTarget in
                        Text(outputTarget.rawValue)
                    }
                }
            }

            Section {
                // 3. User hits 'Go'
                Button{
                    print("Go") }
                label: {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Text("Go")
                            .font(.headline)
                    }
                }
                .disabled(targetFolderURL == nil || fileName.isEmpty || isProcessing)
            }
//        }
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
                        self.targetFolderURL = url
                    }
                }
            case .failure(let error):
                print("Folder selection error: \(error.localizedDescription)")
            }
        }
    }

//    private func runPipelineAndSave() {
//        guard let folderURL = targetFolderURL else { return }
//        isProcessing = true
//
//        DispatchQueue.global(qos: .userInitiated).async {
//            // A. Perform background work / file generation
//            let generatedData = "Sample exported content".data(using: .utf8)!
//
//            // B. Resolve destination path
//            let destinationURL = folderURL.appendingPathComponent(self.fileName)
//
//            do {
//                // C. Automatically save file without prompting again
//                try generatedData.write(to: destinationURL)
//                print("Successfully saved to \(destinationURL.path)")
//            } catch {
//                print("Failed to save file: \(error.localizedDescription)")
//            }
//
//            DispatchQueue.main.async {
//                self.isProcessing = false
//            }
//        }
//    }
}
