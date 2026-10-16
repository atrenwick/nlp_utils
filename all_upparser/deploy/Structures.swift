//
//  Structures.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
//

import Foundation


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

struct RegexLangPatternToLangMap: Identifiable{
    var id = UUID()
    let string: String
    let langValue: Language
    
    var asRegex: Regex<Substring>{
        try! Regex(string)
    }
}

struct RunMetas: Identifiable{
    var id = UUID()
    let lang: String
    let sourceFileURL: URL?
    let sourceFileName: String
    let outputFileName: String
    let treebank : String
    let exportFormat: ExportFormat
    var unread: Bool = true
    let savedURL: URL?
    let message: String
    let safeHeaderAttribs: XmlHeaderAttribs
    let includeConllSentText: Bool
}

struct RunData: Identifiable{
    var id = UUID()
    let sents: [Sentence]
    let exportContent: String
    var tokCount: Int {
        // reduce collection to single element : start at 0, add iteratively over elements
        sents.reduce(0) { $0 + $1.conllData.count }
    }
}

struct RunOutput: Identifiable {
    var id = UUID()
    let runData: RunData
    var runMetas: RunMetas
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

//struct SaveInputMetas: Identifiable{
//    var id = UUID()
//    let lang: Language
//    let displayName: String
//    let inputURL: URL?
//    let saveName: String
//    let targetFolderURL: URL?
//    let exportFormat: ExportFormat
//    let treebank: Language.Treebank
//    let safeHeaderAttribs: XmlHeaderAttribs
//    let includeConllSentText: Bool
//}

struct Sentence : Identifiable {
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
        lineStore.append(contentsOf: conllData.map {$0.form})
        return lineStore.joined(separator: "\n")
    }
    var conll: String {
//        var testText = [""]
         (
            conllData.map {$0.form}
         ).joined(separator: "\n")
//        testText.append(contentsOf: conllData.map {$0.form})
//         testText.joined(separator: "\n")
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
        var lines: [ConllLineContent] = conllData.map { .row($0) }
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
                    tok.xpos, tok.feats, tok.head, tok.deprel,
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
        
        var selectedLanguage: Language
        var selectedTreebank: Language.Treebank
        var maxPipelineStep: PipelineStep
        var runResentenciser: Bool
        var runRetokeniser: Bool
        var tokenizingMethod: TokenizingMethod
        var sentencizingMethod: SentencizingMethod
        var insertNewTokPosition: InsertPosition
        var selectedRetokenisationType: RetokenisationType
        var runExplicit: Bool

        
        // need to add = nil in init of it's to truly allow no parameters to be specified
        init(
            selectedLanguage: Language? = nil,
            selectedTreebank: Language.Treebank? = nil,
            maxPipelineStep: PipelineStep? = nil,
            runResentenciser: Bool? = nil,
            runRetokeniser: Bool? = nil,
            tokenizingMethod: TokenizingMethod? = nil,
            sentencizingMethod: SentencizingMethod? = nil,
            insertNewTokPosition: InsertPosition? = nil,
            selectedRetokenisationType: RetokenisationType? = nil,
            runExplicit: Bool? = nil
        ){
            self.selectedLanguage = TaggerConfig.resolveRepresentable(passed: selectedLanguage, key: "selectedLanguageDefault", fallback: Language.FR )
            self.selectedTreebank = TaggerConfig.resolveRepresentable(passed: selectedTreebank, key: "selectedTreebankDefault", fallback: Language.FR.defaultTB )
            self.runResentenciser = TaggerConfig.resolveBool(passed: runResentenciser, key: "runResentenciserDefault", default: false)
            self.runRetokeniser = TaggerConfig.resolveBool(passed: runRetokeniser, key: "runRetokeniserDefault", default: false)
            self.maxPipelineStep = TaggerConfig.resolveRepresentable(passed: maxPipelineStep, key: "maxPipelineStepDefault", fallback: .step5 )
            self.tokenizingMethod = TaggerConfig.resolveRepresentable(passed: tokenizingMethod, key: "tokenizingMethodDefault", fallback: .nltokeniser )
            self.sentencizingMethod = TaggerConfig.resolveRepresentable(passed: sentencizingMethod, key: "sentencizingMethodDefault", fallback: .nlSentencizer )
            self.insertNewTokPosition = TaggerConfig.resolveRepresentable(passed: insertNewTokPosition, key: "insertNewTokPositionDefault", fallback: .after )
            self.selectedRetokenisationType = TaggerConfig.resolveRepresentable(passed: selectedRetokenisationType, key: "retokenisationTypeDefault", fallback: .predict )
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
        init(
            fileName: String? = nil,
            targetFolderURL: URL? = nil,
            selectedExportFormat: ExportFormat? = nil,
            xmlAuthorName: String? = nil,
            xmlTitle: String? = nil,
            includeConllSentIdLine: Bool? = nil,
            includeConllSentText: Bool? = nil
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
    
    //
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
    
}

// struct for manually tokenised, modified inputs, before conversion to Token
struct TempToken: Identifiable, Hashable {
    var id = UUID()
    var form: String
}

struct Token : Identifiable {
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
    
    var conlluLine: String {
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel].joined(separator: "\t")
    }
    
    var conllRaw: String{
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel, "_","_"].joined(separator: "\t") //+ "\n"
    }
    var conllRawMultitag: String{
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel, col8,col9].joined(separator: "\t") //+ "\n"
    } // this includes NL parser outputs for col8,9, but the funct to make the ExportString doesn't call this prop.
    
    var asXML: String{
                """
                <w tokID=\"\(tokid)\"  form=\"\(form.xmlEscaped)\" lemma=\"\(lemma.xmlEscaped)\" upos=\"\(upos.xmlEscaped)\" xpos=\"\(xpos.xmlEscaped)\" feats=\"\(feats.xmlEscaped)\" head=\"\(head.xmlEscaped)\" deprel=\"\(deprel.xmlEscaped)\">\(form.xmlEscaped)</w>
                """
    }
}

/* dealing with XMLconll docs as input */
struct XMLConllElement {
    let id: String  // send_id extracted with xmlparsing
    let blob: String // content of s.text == conll lines with sent id line added in by parser
}

struct XmlHeaderAttribs{
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

