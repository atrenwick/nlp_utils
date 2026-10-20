//
//  Structures.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
//

import Foundation
import CoreML

struct BuiltSentHolder: Identifiable, Hashable{
    var id = UUID()
    var tempToks: [TempToken]
    
    func toHashableSent(tempToks: [TempToken]) -> HashableSentence? {
        guard tempToks.count > 0 else {return nil }
        return makeHashableSentFromTestToks(tempTokens: tempToks)
    }
    
    func toShowString(tempToks: [TempToken])-> AttributedString {
        guard tempToks.count > 0 else {return "error1" }
        if let hashableSent = makeHashableSentFromTestToks(tempTokens: tempToks){
            return markupTokenisationInSent(hashableSent: hashableSent)
        }
        else {return "error2"}
    }
}

//TODO: update calculated property to use Extension method
struct Document {
    var id = UUID()
    let sentences:[Sentence]
    
    var docAsRaw: String{
        var internalList: [String] = []
        for sentence in sentences {
            internalList.append(sentence.conll)
            internalList.append("\n")
        }
        return internalList.joined(separator: "\n")
    }
}

struct ExporterService {
    /// Writes processing output string directly to a user-selected folder URL
    static func exportDataToFile(
        exportContent: String,
        customName: String,
        targetFolderURL: URL,
        exportFormat: ExportFormat,
        runExplicit: Bool
        
    ) throws -> URL {
        let fileExtension = exportFormat.fileExtension
      
        if runExplicit{
            print("step1 success")
        }
        // 2. Format sanitized filename
        var safeName = customName.sanitizedFileName
        if !safeName.hasSuffix(".\(fileExtension)") {
                    safeName += ".\(fileExtension)"
                }
        if runExplicit{
            print("step2 success")
        }
        // 3. Construct destination path inside the chosen directory
        let destinationFileURL = targetFolderURL.appendingPathComponent(safeName)
        if runExplicit{
            print("step3 success")
        }
        // 4. Elevate security permissions for external directory write
        let gotAccess = targetFolderURL.startAccessingSecurityScopedResource()
        defer {
            if gotAccess {
                targetFolderURL.stopAccessingSecurityScopedResource()
                if runExplicit{
                    print("step4 success")
                }
            }
        }
        
        // 5. Write
        try exportContent.write(to: destinationFileURL, atomically: true, encoding: .utf8)
        if runExplicit{
            print("step5 success URL == \(destinationFileURL.path())")
        }
        return destinationFileURL
    }
}

struct HashableSentence: Hashable {
    // sentence as id + list of strings as input for parser
    let id: String
    let tokens: [String]
    let conllMetas: [String]
    var detokenised: String {
        tokens.joined(separator: " ")
    }
}

struct LabelVocabsForBERTlike {
// MARK: - Label vocabularies for BERT derived models :: 4x vocabs with loader
/// The five vocabularies that turn output indices back into labels. They must come from
/// the same training run as the model (train_bert.py writes them next to it); the old
/// BiLSTM vocabularies number the labels differently.
    let upos: Vocab
    let feats: Vocab
    let deprel: Vocab
    let lemmaRule: Vocab
    
    static func loadLabelVocabularies(languageCode: String,
                                      treebank: String,
                                      bundle: Bundle = .main
    ) throws -> LabelVocabsForBERTlike {
        
        func vocab(_ label: String) throws -> Vocab {
            let name = "\(languageCode)_distilbert_\(label)_vocab_\(treebank)"
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw PipelineError.missingResource("\(name).json")
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(VocabData.self, from: data)
            return Vocab(data: decoded)
        }

        return LabelVocabsForBERTlike(
            upos: try vocab("upos"),
            feats: try vocab("feats"),
            deprel: try vocab("deprel"),
            lemmaRule: try vocab("lemma_rule")
        )
    }
}

struct LogitReaderForBERTlike {
// MARK: - Reading Core ML output arrays for bert-derived models to deal with padding
/// Reads values out of an MLMultiArray without boxing every element. Honours the array's
/// strides (Core ML may pad rows) and its element type (the model's outputs are normally
/// float16; float32 and double are handled too).

    private let array: MLMultiArray             // keeps the buffer alive
    private let base: UnsafeRawPointer
    private let dataType: MLMultiArrayDataType
    private let strides: [Int]
    private let shape: [Int]

    /// - Parameters:
    ///   - rank: expected number of dimensions (3 = [1, rows, width], 4 = [1, channels, rows, columns])
    ///   - rows: how many rows the caller will read (words + 1)
    ///   - labels: the vocabulary size this array's label dimension must match (nil to skip)
    init(_ output: MLFeatureProvider, _ name: String, rank: Int, rows: Int,
         labels: Int? = nil) throws  {
        guard let array = output.featureValue(for: name)?.multiArrayValue else {
            throw PipelineError.unexpectedOutput("\(name) is missing")
        }

        let shape = array.shape.map { $0.intValue }
        guard shape.count == rank, shape[rank - 2] >= rows else {
            throw PipelineError.unexpectedOutput("\(name) has shape \(shape); expected rank \(rank) with at least \(rows) rows")
        }
        if let labels {
            let width = rank == 3 ? shape[2] : shape[1]
            guard width == labels else {
                throw PipelineError.unexpectedOutput("\(name) has \(width) labels but the vocabulary has \(labels); the vocabulary files and the model are from different training runs")
            }
        }
       switch array.dataType {
        case .float16, .float32, .double: break
        default: throw PipelineError.unexpectedOutput("\(name) has an unsupported element type")
        }
        self.array = array
        self.base = UnsafeRawPointer(array.dataPointer)
        self.dataType = array.dataType
        self.strides = array.strides.map { $0.intValue }
        self.shape = shape
    }

    /// rank 3: value at [0, row, column]
    func value(row: Int, column: Int) -> Float {
        load(strides[1] * row + strides[2] * column)
    }

    /// rank 3: index of the largest value in a row (over the last dimension)
    func argmax(row: Int) -> Int {
        var best = 0
        var bestValue = -Float.infinity
        for k in 0..<shape[2] {
            let v = value(row: row, column: k)
            if v > bestValue { bestValue = v; best = k }
        }
        return best
    }

    /// rank 4 ([1, channels, rows, columns]): value at [0, channel, row, column]
    func value(channel: Int, row: Int, column: Int) -> Float {
        load(strides[1] * channel + strides[2] * row + strides[3] * column)
    }

    private func load(_ offset: Int) -> Float {
        switch dataType {
        case .float32:
            return base.load(fromByteOffset: offset * 4, as: Float.self)
        case .double:
            return Float(base.load(fromByteOffset: offset * 8, as: Double.self))
        default:                                    // .float16, checked in init
            return Self.float(fromHalfBits: base.load(fromByteOffset: offset * 2, as: UInt16.self))
        }
    }


    /// IEEE half -> Float by bit manipulation, so no Float16 type is needed (it isn't
    /// available when building for Intel simulators).
    private static func float(fromHalfBits h: UInt16) -> Float {
        let sign = UInt32(h >> 15) << 31
        let exponent = UInt32((h >> 10) & 0x1F)
        let mantissa = UInt32(h & 0x3FF)
        switch exponent {
        case 0:
            let magnitude = Float(mantissa) / 16_777_216        // subnormal (or zero): mantissa * 2^-24
            return sign == 0 ? magnitude : -magnitude
        case 0x1F:
            return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13))   // infinity / NaN
        default:
            return Float(bitPattern: sign | ((exponent + 112) << 23) | (mantissa << 13))
        }
    }
}


struct RegexLangPatternToLangMap: Identifiable{
    var id = UUID()
    let string: String
    let langValue: Language
    
    var asRegex: Regex<Substring>{
        try! Regex(string)
    }
}

struct ResultStorageManager {
    @discardableResult
    static func getRunsDirectory() throws -> URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let runsURL = documents.appendingPathComponent("runs", isDirectory: true)

        do {  // Automatically creates the folder if it's missing
            try FileManager.default.createDirectory(at: runsURL, withIntermediateDirectories: true, attributes: nil)
            return runsURL
        } catch {
            print("Failed to create 'runs' directory: \(error)")
            throw PipelineError.outputFolderCreationError
        }
    }

    static func save(_ runOutput: RunOutput) throws ->URL? {
        guard let runsFolder = try getRunsDirectory() else { throw PipelineError.outputFolderCreationError }
        let fileURL = runsFolder.appendingPathComponent("\(runOutput.id).json")
        
        do {
            let data = try JSONEncoder().encode(runOutput)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            print("Successfully saved to: \(fileURL.path)")
            return fileURL
        } catch {
            print("Failed to save result: \(error)")
            throw PipelineError.fileSaveError(filename: fileURL.absoluteString)
        }
    }

    static func load(runID: String) throws -> RunOutput? {
        guard let runsFolder = try getRunsDirectory() else { throw PipelineError.outputFolderCreationError }
        let fileURL = runsFolder.appendingPathComponent("\(runID).json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(RunOutput.self, from: data)
        } catch {
            print("Failed to load result: \(error)")
            return nil
        }
    }
}

struct RunData: Identifiable, Codable {
    var id = UUID()
    let runID: String
    let sents: [Sentence]
    let exportContent: String
    var tokCount: Int {
        // reduce collection to single element : start at 0, add iteratively over elements
        sents.reduce(0) { $0 + $1.conllData.count }
    }
}

struct RunFileWrapper: Decodable {
    let id: UUID
    let runMetas: RunMetas
}

struct RunMetas: Identifiable, Codable {
    //mod
    let id = UUID()
    let runID: String
    let exportFormat: ExportFormat
    let includeConllSentIdLine: Bool
    let includeConllSentText: Bool
    let inputFileType: InputFileType
    let lang: String
    let maxPipelineStep: PipelineStep
    let message: String
    let outputFileName: String
    let processedCount: Int
    let runResentenciser: Bool
    let runRetokeniser: Bool
    let safeHeaderAttribs: XmlHeaderAttribs
    let savedURL: URL?
    let selectedRetokenisationType: RetokenisationType
    let sentencizingMethod: SentencizingMethod
    let sourceFileName: String
    let sourceFileURL: URL?
    let targetFolderURL: URL?
    let tokenizingMethod: TokenizingMethod
    let totalCount: Int
    let treebank : String
    var unread: Bool = true
    
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "SavedData")
        }
    }
}


struct RunOutput: Identifiable, Codable {
    var id = UUID()
    let runID: String
    let runData: RunData
    var runMetas: RunMetas
}

struct RunSelectorHelper{
    let runMetas: RunMetas
    let jsonFile: URL
}

struct SandboxImporter {
    /// Copies or writes external file data into the app's local Documents directory.
    static func importToSandbox(from externalURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Ensure a unique local filename so existing files aren't overwritten
        let targetURL = docsDir.appendingPathComponent(externalURL.lastPathComponent)
        
        // Remove old instance if it exists at target path
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        
        // Copy the file into your app's local sandbox memory space
        try fileManager.copyItem(at: externalURL, to: targetURL)
        
        return targetURL
    }
}

struct Sentence : Identifiable, Codable {
    var id = UUID()
    let sentID: String
    let conllData: [Token]
    let conllMetas: [String]

    var tokCount: Int {
        conllData.count
    }
    var runSentIdRegexes: String{
        var content = sentID.trimmingCharacters(in: .newlines)
        // 2. Remove existing header if any
        let pattern = #"^\s*#\s*sent_id\s*=\s*"#
            if let range = content.range(of: pattern, options: .regularExpression) {
                content.removeSubrange(range)
            }
        // 3. Re-trim ONLY newlines from the payload before applying header
        content = content.trimmingCharacters(in: .newlines)
        return content
    }
    
    var conllMetaTextLine: String {
        var internalList: [String] = ["# sent_text = "]
        internalList.append(contentsOf: conllData.map {$0.form})
        return internalList.joined(separator: " ")
    }
    
    var sentIdAsMeta: String {
        return "\n\n# sent_id = \(runSentIdRegexes)"
    }
    
    func makeXMLsent(exportFormat: ExportFormat, includeConllSentText: Bool) -> String {
        var xmlTokenElements: [String] = []
        let sentHeader = """
        <s id=\"\(runSentIdRegexes)\">
        """
        let sentFooter = """
            </s>
            """
        
        xmlTokenElements.append(sentHeader)
        if includeConllSentText {
            xmlTokenElements.append("# sent_id = \(runSentIdRegexes)")
            xmlTokenElements.append(conllMetaTextLine)
        }

        switch exportFormat{
        case .xml:
            xmlTokenElements.append(conllData.makeSentenceXML())
        case .xmlConll:
            xmlTokenElements.append(conllData.makeSentenceXMLconll())
        default:
            return ""
        }
        xmlTokenElements.append(sentFooter)
        return xmlTokenElements.joined(separator: "\n")
    }
    func makeConll(sentInMeta: Bool = true) -> String {
        var lineStore: [String] = []
        lineStore.append(sentIdAsMeta)

        if sentInMeta {
            var sentTextLine = ["# sent = "]
            sentTextLine.append(contentsOf: conllData.map {$0.form} )
            lineStore.append(sentTextLine.joined(separator: " "))
        }
        lineStore.append(contentsOf: conllData.map {$0.conllRaw})
        return lineStore.joined(separator: "\n")
    }
    var conll: String {
        var conllString = ["\n# sent_id = \(sentID)"]
        conllString.append(contentsOf: conllData.map {$0.conlluLine} )
        return conllString.joined(separator: "\n")
    }
    
    var conllTidy: String {
        var internalLineList: [String] = []
        for item in formatTidy(){
            internalLineList.append(item)
        }
        return internalLineList.joined(separator: "\n")
    }

    var hashableSentence: HashableSentence{
        //convert to TokenisedSentence for parsing
        var internalTokList: [String] = []
        for token in conllData{
            internalTokList.append(token.form)
        }
        return HashableSentence(id: sentID, tokens: internalTokList, conllMetas: self.conllMetas)
    }
    
    func formatRaw() -> [String]{
        
        var lines: [ConllLineContent] = conllData.map { .row($0) }
        lines.append(.blank)
        var result = lines.map { line in
            switch line {
            case .row(let tok): return tok.conllRaw
            case .blank: return ""
            }
        }
        result.insert("\n\(sentID)", at: 0)
        return result
    }

    /// Use string count to column-align rows of each sent  independently
    func formatTidy() -> [String] {
        //get lines, add blank for end
        let lines: [ConllLineContent] = conllData.map { .row($0) }
        var result: [String] = []
        result.append(sentIdAsMeta)
        var currentRows: [[String]] = []
        
        func flushSentence() {
            // calculate how to make tidy cols, make tidy cols
            guard let columnCount = currentRows.first?.count else { return }
            var widths = Array(repeating: 0, count: columnCount)
            for row in currentRows {
                for (i, field) in row.enumerated() {
                    widths[i] = max(widths[i], field.count)
                }
            }
            for row in currentRows {
                let padded = row.enumerated().map { i, field in
                    field.padding(toLength: widths[i], withPad: " ", startingAt: 0)
                }
                result.append(padded.joined(separator: "  "))
            }
            currentRows = []
        }

        //process toks, flush, append
        for line in lines {
            switch line {
            case .row(let tok):
                currentRows.append([
                    String(tok.tokid), tok.form, tok.lemma, tok.upos,
                    tok.xpos, tok.feats, tok.head, tok.deprel, tok.col8, tok.col9
                ])
            case .blank:
                flushSentence()
                result.append("")
            }
        }
        flushSentence() // in case the input didn't end with a trailing .blank
        return result
    }
}


struct TaggerConfig{
    // MARK: vars to bring in substructs
    var id = UUID()
    var inputConfig: InputConfig
    var parsingConfig: ParsingConfig
    var exportConfig: ExportConfig
    var progressConfig: ProgressConfig
    var inputData: InputData
    var outputData : OutputData
    // var reportingConfig: ReportingConfig
    // var visibilityConfig: VisibilityConfig
    
    struct InputConfig{
        var inputFileType: InputFileType
        var selectedInputFile: URL?
        var displayName: String
        var detectLanguage: Bool
        init(
            inputFileType: InputFileType? = nil,
            detectLanguage: Bool? = nil,
            displayName: String? = nil,
            selectedInputFile: URL? = nil
        ){
            self.inputFileType = TaggerConfig.resolveRepresentable(passed: inputFileType, key: "inputFileTypeDefault", fallback: InputFileType.txt )
            self.detectLanguage = TaggerConfig.resolveBool(passed: detectLanguage, key: "detectLangDefault", default: false)
            self.displayName = ""
        }
    }
    
    struct ParsingConfig{
        var selectedArchitecture: ModelArchitecture
        var selectedLanguage: Language
        var selectedTreebank: Language.Treebank
        var maxPipelineStep: PipelineStep
        var modelArchitecture: ModelArchitecture
        var runResentenciser: Bool
        var runRetokeniser: Bool
        var tokenizingMethod: TokenizingMethod
        var sentencizingMethod: SentencizingMethod
        var insertNewTokPosition: InsertPosition
        var selectedRetokenisationType: RetokenisationType
        var priLemSource: LemmaSource
        var secLemSource: LemmaSource
        var getSecLems: Bool
        var runExplicit: Bool

        
        // need to add = nil in init of it's to truly allow no parameters to be specified
        init(
            selectedArchitecture: ModelArchitecture? = nil,
            selectedLanguage: Language? = nil,
            selectedTreebank: Language.Treebank? = nil,
            maxPipelineStep: PipelineStep? = nil,
            modelArchitecture: ModelArchitecture? = nil,
            runResentenciser: Bool? = nil,
            runRetokeniser: Bool? = nil,
            tokenizingMethod: TokenizingMethod? = nil,
            sentencizingMethod: SentencizingMethod? = nil,
            insertNewTokPosition: InsertPosition? = nil,
            selectedRetokenisationType: RetokenisationType? = nil,
            priLemSource: LemmaSource? = nil,
            secLemSource: LemmaSource? = nil,
            getSecLems: Bool? = nil,
            runExplicit: Bool? = nil
        ){
            self.selectedArchitecture = TaggerConfig.resolveRepresentable(passed: selectedArchitecture, key: "ModelArchitectureDefault", fallback: ModelArchitecture.cnnBiLSTM )
            self.selectedLanguage = TaggerConfig.resolveRepresentable(passed: selectedLanguage, key: "selectedLanguageDefault", fallback: Language.FR )
            self.selectedTreebank = TaggerConfig.resolveRepresentable(passed: selectedTreebank, key: "selectedTreebankDefault", fallback: Language.FR.defaultTB )
            self.runResentenciser = TaggerConfig.resolveBool(passed: runResentenciser, key: "runResentenciserDefault", default: false)
            self.runRetokeniser = TaggerConfig.resolveBool(passed: runRetokeniser, key: "runRetokeniserDefault", default: false)
            self.modelArchitecture = TaggerConfig.resolveRepresentable(passed: modelArchitecture, key: "modelArchitectureDefault", fallback: .cnnBiLSTM)
            self.maxPipelineStep = TaggerConfig.resolveRepresentable(passed: maxPipelineStep, key: "maxPipelineStepDefault", fallback: .step5 )
            self.tokenizingMethod = TaggerConfig.resolveRepresentable(passed: tokenizingMethod, key: "tokenizingMethodDefault", fallback: .nltokeniser )
            self.sentencizingMethod = TaggerConfig.resolveRepresentable(passed: sentencizingMethod, key: "sentencizingMethodDefault", fallback: .nlSentencizer )
            self.insertNewTokPosition = TaggerConfig.resolveRepresentable(passed: insertNewTokPosition, key: "insertNewTokPositionDefault", fallback: .after )
            self.selectedRetokenisationType = TaggerConfig.resolveRepresentable(passed: selectedRetokenisationType, key: "retokenisationTypeDefault", fallback: .predict )
            self.priLemSource = TaggerConfig.resolveRepresentable(passed: priLemSource, key: "priLemSourceDefault", fallback: .hybrid )
            self.secLemSource = TaggerConfig.resolveRepresentable(passed: secLemSource, key: "secLemSourceDefault", fallback: .rule )
            self.getSecLems = TaggerConfig.resolveBool(passed: getSecLems, key: "getSecLemsDefault")
            self.runExplicit = TaggerConfig.resolveBool(passed: runExplicit, key: "runExplicifDefault")
        }
    }
    struct ExportConfig{
        var fileName: String
        var targetFolderURL: URL?
        var selectedExportFormat: ExportFormat
        var xmlAuthorName: String
        var xmlTitle: String
        var includeConllSentIdLine: Bool
        var includeConllSentText: Bool
        var getsubtokens: Bool
        init(
            fileName: String? = nil,
            targetFolderURL: URL? = nil,
            selectedExportFormat: ExportFormat? = nil,
            xmlAuthorName: String? = nil,
            xmlTitle: String? = nil,
            includeConllSentIdLine: Bool? = nil,
            includeConllSentText: Bool? = nil,
            getsubtokens: Bool? = nil
        ) {
            self.fileName = TaggerConfig.resolveString(passed: fileName, key: "fileNameDefault")
            self.targetFolderURL = targetFolderURL
            ?? URL(string: UserDefaults.standard.string(forKey: "outputDirDefault") ?? "")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            
            self.selectedExportFormat = TaggerConfig.resolveRepresentable(passed: selectedExportFormat, key: "selectedExportFormatDefault", fallback: .xml )
            self.xmlAuthorName = TaggerConfig.resolveString(passed: xmlAuthorName, key: "xmlAuthorDefault" )
            self.xmlTitle = TaggerConfig.resolveString(passed: xmlTitle, key: "xmlTitleDefault")
            self.includeConllSentIdLine = TaggerConfig.resolveBool(passed: includeConllSentIdLine, key: "includeConllSentIdLineDefault", default: true )
            self.includeConllSentText = TaggerConfig.resolveBool(passed: includeConllSentText, key: "includeConllSentTextDefault", default: true )
            self.getsubtokens = TaggerConfig.resolveBool(passed: getsubtokens, key: "getsubtokensDefault", default: false )
        }
    }
    struct ProgressConfig{
        var appleProgress: Progress
        var progressBarStyle: ProgressBarStyle
        var startTime: Date?
        var alertMessage: String?
        var exportStatusMessage: String?
        var processedCount: Int
        var totalCount: Int
        var hasStarted: Bool
        init(
            appleProgress: Progress? = nil,
            progressBarStyle: ProgressBarStyle? = nil,
            startTime: Date? = nil,
            alertMessage: String? = nil,
            exportStatusMessage: String? = nil,
            processedCount: Int? = nil,
            totalCount: Int? = nil,
            hasStarted: Bool? = nil,
        ){
            self.appleProgress = Progress(totalUnitCount: 1)
            self.progressBarStyle = TaggerConfig.resolveRepresentable(passed: progressBarStyle, key: "progressBarStyleDefault", fallback: .apple)
            self.startTime = nil
            self.alertMessage = nil
            self.exportStatusMessage = nil
            self.processedCount = 0
            self.totalCount = 0
            self.hasStarted = false
        }
        
        mutating func reset(){
            self.appleProgress = Progress(totalUnitCount: 1)
            self.startTime = nil
            self.alertMessage = nil
            self.exportStatusMessage = nil
            self.processedCount = 0
            self.totalCount = 0
            self.hasStarted = false
        }
    }
    //    // sentences ::
    struct InputData{
        var allSentences: [HashableSentence]
        var builtSents: [BuiltSentHolder]
        var sentsToRetokenise: [String]
        var resentencizerOutputStrings: [String]
        init(
            allSentences: [HashableSentence]? = nil,
            builtSents: [BuiltSentHolder]? = nil,
            sentsToRetokenise: [String]? = nil,
            resentencizerOutputStrings: [String]? = nil,
        )
        {
            self.allSentences = []
            self.builtSents = []
            self.sentsToRetokenise = []
            self.resentencizerOutputStrings = []
        }
        mutating func reset(){
            self = Self()
        }
    }
    
    struct OutputData{
        var topLevelOutputList: [RunOutput]
        var outputString: String
        var runOutput: RunOutput?
        var exportContent: String = ""
        var safeHeaderAttribs: XmlHeaderAttribs
        var outSents: [Sentence]
        
        init(
            topLevelOutputList: [RunOutput]? = nil,
            outputString: String? = nil,
            runOutput: RunOutput? = nil,
            builtSents: [BuiltSentHolder]? = nil,
            sentsToRetokenise: [String]? = nil,
            exportContent: String? = nil,
            safeHeaderAttribs: XmlHeaderAttribs? = nil,
            resentencizerOutputStrings: [String]? = nil,
            outSents: [Sentence]? = nil
        )
        {
            self.topLevelOutputList = []
            self.outputString = ""
            self.runOutput = nil
            self.exportContent = ""
            self.safeHeaderAttribs = XmlHeaderAttribs()
            self.outSents = []
        }
        mutating func reset(){
            self = Self() // reinit
        }
    }
    
    //
    
    // top level init
    init(
        parsingConfig: ParsingConfig = ParsingConfig(),
        inputConfig: InputConfig = InputConfig(),
        exportConfig: ExportConfig = ExportConfig(),
        progressConfig: ProgressConfig = ProgressConfig(),
        inputData: InputData = InputData(),
        outputData: OutputData = OutputData()
    ) {
        self.parsingConfig = parsingConfig
        self.inputConfig = inputConfig
        self.exportConfig = exportConfig
        self.progressConfig = progressConfig
        self.inputData = inputData
        self.outputData = outputData
    }
    
    // MARK: - Centralized Static Solvers
    static func resolveBool(passed: Bool?, key: String, default fallback: Bool = false) -> Bool {
        if let value = passed { return value }
        // Check if key exists, otherwise return the fallback default
        return UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : fallback
    }
    // for strings,
    static func resolveString(passed: String?, key: String, default fallback: String = "") -> String {
        if let value = passed { return value }
        return UserDefaults.standard.string(forKey: key) ?? fallback
    }
    // Overloaded resolvers for string and Int backed enums
    static func resolveRepresentable<T: RawRepresentable>(passed: T?, key: String, fallback: T) -> T where T.RawValue == String {
        if let value = passed { return value }
        
        // Try reading the raw string from UserDefaults and converting it back to the enum
        if let savedString = UserDefaults.standard.string(forKey: key),
           let enumValue = T(rawValue: savedString) {
            return enumValue
        }
        return fallback
    }
        static func resolveRepresentable<T: RawRepresentable>(passed: T?, key: String, fallback: T) -> T where T.RawValue == Int {
        if let value = passed { return value }
        
        // Note: Using object(forKey:) as? Int avoids UserDefaults' default '0' bug
        // if the key hasn't been saved yet.
        if let savedInt = UserDefaults.standard.object(forKey: key) as? Int,
           let enumValue = T(rawValue: savedInt) {
            return enumValue
        }
        return fallback
    }
    mutating func runResetters(){
        progressConfig.reset()
        inputData.reset()
        outputData.reset() // full reinit
        print("Running resetters")
        
    }
    
}

// struct for manually tokenised, modified inputs, before conversion to Token
struct TempToken: Identifiable, Hashable {
    var id = UUID()
    var form: String
}

struct Token : Identifiable, Codable {
    var id = UUID()
    let tokid: Int
    let form: String
    let lemma: String
    let upos: String
    let xpos: String
    let feats: String
    let head: String
    let deprel: String
    let col8: String
    let col9: String
    let subTokens: [String]?
    
    var conlluLine: String {
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel, col8, col9].joined(separator: "\t")
    }
    
//    var conllRaw: String{
//        [String(tokid), form, lemma, upos, xpos, feats, head, deprel, "_","_"].joined(separator: "\t") //+ "\n"
//    }
    var conllRaw: String{
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel, col8,col9].joined(separator: "\t") //+ "\n"
    } // this includes NL parser outputs for col8,9, but the funct to make the ExportString doesn't call this prop.
    
    var asXML: String{
                """
                <w tokID=\"\(tokid)\"  form=\"\(form.xmlEscaped)\" lemma=\"\(lemma.xmlEscaped)\" upos=\"\(upos.xmlEscaped)\" xpos=\"\(xpos.xmlEscaped)\" feats=\"\(feats.xmlEscaped)\" head=\"\(head.xmlEscaped)\" deprel=\"\(deprel.xmlEscaped)\" secLem=\"\(col8.xmlEscaped)\" col9=\"\(col9.xmlEscaped)\">\(form.xmlEscaped)</w>
                """
    }
}
// MARK: - Vocabulary
//structure to decode the vocab data JSON file
struct VocabData: Decodable {
    let itos: [String]
    let pad: String
    let unk: String
}
//define the vocab class
final class Vocab {
    let itos: [String]
    let stoi: [String: Int]
    let pad: String
    let unk: String
    
    //   //init method for the vocab class
    init(data: VocabData) {
        itos = data.itos
        pad = data.pad
        unk = data.unk
        var map = [String: Int](minimumCapacity: data.itos.count)
        for (i, s) in data.itos.enumerated() { map[s] = i }
        stoi = map
    }

    var unkId: Int { stoi[unk] ?? 1 }

    func encode(_ token: String) -> Int {
        stoi[token] ?? unkId
    }

    func decode(_ id: Int) -> String {
        (id >= 0 && id < itos.count) ? itos[id] : unk
    }

    //func to get path to file, load, decode and return decoded data based on name of json file
    static func load(named name: String, bundle: Bundle = .main) throws -> Vocab {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw PipelineError.missingResource("\(name).json")
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(VocabData.self, from: data)
        return Vocab(data: decoded)
    }
}


/* dealing with XMLconll docs as input */
struct XMLConllElement {
    let id: String  // send_id extracted with xmlparsing
    let blob: String // content of s.text == conll lines with sent id line added in by parser
}

struct XmlHeaderAttribs : Codable{
    var xmlTitle: String
    var xmlAuthorName: String
    var lang: String
    var treebank: String
    var taggingDate: String
    var sourceFile: String
    var runID: String
    var maxPipelineStep: String
    var runRetokeniser: String
    var tokenizingMethod: String
    var sentencizingMethod: String
    init(
        xmlTitle: String? = nil,
        xmlAuthorName: String? = nil,
        lang: String? = nil,
        treebank: String? = nil,
        taggingDate: String? = nil,
        sourceFile: String? = nil,
        runID: String? = nil,
        maxPipelineStep: String? = nil,
        runRetokeniser: String? = nil,
        tokenizingMethod: String? = nil,
        sentencizingMethod: String? = nil
    ) {
        self.xmlTitle = "xmlTitle"
        self.xmlAuthorName = "xmlAuthorName"
        self.lang = "lang"
        self.treebank = "treebank"
        self.taggingDate = "taggingDate"
        self.sourceFile = "sourceFile"
        self.runID = "runID"
        self.maxPipelineStep = "maxPipelineStep"
        self.runRetokeniser = "runRetokeniser"
        self.tokenizingMethod = "tokenizingMethod"
        self.sentencizingMethod = "sentencizingMethod"
    }
}

