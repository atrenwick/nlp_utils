//
//  TaggerConfig.swift
//  Tagger
//
//  Created by Adam on 28/10/2026.
//  Structure containing settings, etc for tagging runs

import Foundation


struct TaggerConfig{
    // MARK: vars to bring in substructs
    var id = UUID()
    var inputConfig: InputConfig
    var parsingConfig: ParsingConfig
    var exportConfig: ExportConfig
    var progressConfig: ProgressConfig
    var inputData: InputData
    var outputData : OutputData
    
    struct InputConfig{
        var inputFileType: InputFileType
        var selectedInputFile: URL?
        var displayName: String
        var detectLanguage: Bool
        var matchFileNameType: Bool
        init(
            inputFileType: InputFileType? = nil,
            detectLanguage: Bool? = nil,
            matchFileNameType: Bool? = nil,
            displayName: String? = nil,
            selectedInputFile: URL? = nil
        ){
            self.inputFileType = TaggerConfig.resolveRawRep(passed: inputFileType, key: "inputFileTypeDefault", fallback: InputFileType.txt )
            self.detectLanguage = TaggerConfig.resolveBool(passed: detectLanguage, key: "detectLangDefault", default: false)
            self.matchFileNameType = TaggerConfig.resolveBool(passed: matchFileNameType, key: "matchFileNameTypeDefault", default: false)
            self.displayName = String(UUID().uuidString.prefix(5))
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
        var loadingStatusMessage: String
        var loadingProgress: Double
        var loadingComplete: Bool
        var maxSeqLen: Int
        var maxWords: Int
        
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
            runExplicit: Bool? = nil,
            loadingStatusMessage: String? = nil,
            loadingProgress: Double? = nil,
            loadingComplete: Bool? = nil,
            maxSeqLen: Int? = nil,
            maxWords: Int? = nil
        ){
            self.selectedArchitecture = TaggerConfig.resolveRawRep(passed: selectedArchitecture, key: "modelArchitectureDefault", fallback: ModelArchitecture.cnnBiLSTM )
            self.selectedLanguage = TaggerConfig.resolveRawRep(passed: selectedLanguage, key: "selectedLanguageDefault", fallback: Language.FR )
            self.selectedTreebank = TaggerConfig.resolveRawRep(passed: selectedTreebank, key: "selectedTreebankDefault", fallback: Language.FR.defaultTB )
            self.runResentenciser = TaggerConfig.resolveBool(passed: runResentenciser, key: "runResentenciserDefault", default: false)
            self.runRetokeniser = TaggerConfig.resolveBool(passed: runRetokeniser, key: "runRetokeniserDefault", default: false)
            self.modelArchitecture = TaggerConfig.resolveRawRep(passed: modelArchitecture, key: "modelArchitectureDefault", fallback: .cnnBiLSTM)
            self.maxPipelineStep = TaggerConfig.resolveRawRep(passed: maxPipelineStep, key: "maxPipelineStepDefault", fallback: .step5 )
            self.tokenizingMethod = TaggerConfig.resolveRawRep(passed: tokenizingMethod, key: "tokenizingMethodDefault", fallback: .nltokeniser )
            self.sentencizingMethod = TaggerConfig.resolveRawRep(passed: sentencizingMethod, key: "sentencizingMethodDefault", fallback: .nlSentencizer )
            self.insertNewTokPosition = TaggerConfig.resolveRawRep(passed: insertNewTokPosition, key: "insertNewTokPositionDefault", fallback: .after )
            self.selectedRetokenisationType = TaggerConfig.resolveRawRep(passed: selectedRetokenisationType, key: "retokenisationTypeDefault", fallback: .predict )
            self.priLemSource = TaggerConfig.resolveRawRep(passed: priLemSource, key: "priLemSourceDefault", fallback: .hybrid )
            self.secLemSource = TaggerConfig.resolveRawRep(passed: secLemSource, key: "secLemSourceDefault", fallback: .rule )
            self.getSecLems = TaggerConfig.resolveBool(passed: getSecLems, key: "getSecLemsDefault")
            self.runExplicit = TaggerConfig.resolveBool(passed: runExplicit, key: "runExplicifDefault")
            self.maxWords = -1
            self.maxSeqLen = 2
            self.loadingStatusMessage = ""
            self.loadingProgress  = 0.0
            self.loadingComplete = false
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
            self.fileName = TaggerConfig.resolveString(passed: fileName, key: "fileName") == "" ? GeneralOutputMakingWorkflow.makeFilename() : TaggerConfig.resolveString(passed: fileName, key: "fileName")
            self.targetFolderURL = targetFolderURL
            ?? URL(string: UserDefaults.standard.string(forKey: "outputDirDefault") ?? "")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            
            self.selectedExportFormat = TaggerConfig.resolveRawRep(passed: selectedExportFormat, key: "selectedExportFormatDefault", fallback: .xml )
            self.xmlAuthorName = TaggerConfig.resolveString(passed: xmlAuthorName, key: "xmlAuthorDefault" )
            self.xmlTitle = TaggerConfig.resolveString(passed: xmlTitle, key: "xmlTitleDefault")
            self.includeConllSentIdLine = TaggerConfig.resolveBool(passed: includeConllSentIdLine, key: "includeConllSentIdLineDefault", default: true )
            self.includeConllSentText = TaggerConfig.resolveBool(passed: includeConllSentText, key: "includeConllSentTextDefault", default: true )
            self.getsubtokens = TaggerConfig.resolveBool(passed: getsubtokens, key: "getsubtokensDefault", default: true )
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
        var loadTotalCount: Int
        var loadedCount: Int
        var loadingComplete: Bool
        init(
            appleProgress: Progress? = nil,
            progressBarStyle: ProgressBarStyle? = nil,
            startTime: Date? = nil,
            alertMessage: String? = nil,
            exportStatusMessage: String? = nil,
            processedCount: Int? = nil,
            totalCount: Int? = nil,
            hasStarted: Bool? = nil,
            loadTotalCount: Int? = nil,
            loadedCount: Int? = nil,
            loadingComplete: Bool? = nil
        ){
            self.appleProgress = Progress(totalUnitCount: 1)
            self.progressBarStyle = TaggerConfig.resolveRawRep(passed: progressBarStyle, key: "progressBarStyleDefault", fallback: .apple)
            self.startTime = nil
            self.alertMessage = nil
            self.exportStatusMessage = nil
            self.processedCount = 0
            self.totalCount = 0
            self.hasStarted = false
            self.loadTotalCount = 0
            self.loadedCount = 0
            self.loadingComplete = false
        }
        
        mutating func reset(){
            self.appleProgress = Progress(totalUnitCount: 1)
            self.startTime = nil
            self.alertMessage = nil
            self.exportStatusMessage = nil
            self.processedCount = 0
            self.totalCount = 0
            self.hasStarted = false
            self.loadTotalCount = 0
            self.loadedCount = 0
            self.loadingComplete = false
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
        var topLevelOutputList: [RunOutput] = []
        var outputString: String = ""
        var runOutput: RunOutput?
        var exportContent: String = ""
        var safeHeaderAttribs: XmlHeaderAttribs = XmlHeaderAttribs()
        var outSents: [Sentence] = []
        var outErrors: [OutputError] = []
        
        mutating func reset(){
            self = Self() // reinit
        }
    }
    
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
    static func resolveRawRep<T: RawRepresentable>(passed: T?, key: String, fallback: T) -> T where T.RawValue == String {
        if let value = passed { return value }
        
        // Try reading the raw string from UserDefaults and converting it back to the enum
        if let savedString = UserDefaults.standard.string(forKey: key),
           let enumValue = T(rawValue: savedString) {
            return enumValue
        }
        return fallback
    }
        static func resolveRawRep<T: RawRepresentable>(passed: T?, key: String, fallback: T) -> T where T.RawValue == Int {
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
