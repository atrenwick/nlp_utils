//
//  ClassMethods.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
// methods for use across classes

import CoreML
import Foundation
import NaturalLanguage

// MARK: - MLMultiArray helpers
// can be called in debug to get, show logits…
func dumpScalars(_ text: String, maxChars: Int = 50) {
    // called in runTest() function
    for scalar in text.unicodeScalars.prefix(maxChars) {
        print("\(scalar) -> \(scalar.value)")
    }
}

// MARK: - CoNLL Parsing
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                              CoNLL parsing functions
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//  Main functions:: Bundle loads file -> String == 1 blob
//  1. conllBlobToChunks turns blob into 1 chunk per sentence
//  2. conllChunksToLines takes chunks and gives 1 line per token + metas
//  3. conllLinesToSents takes tokens + metas as lines -> Sentence object with [Tokens]
//  4. makeConllLinesFromURL runs  functions 1-2, in sequence, input== URL
//  5. makeConllLinesFromFile runs the same functions, 1-2, input == String
//  6. Make ConllLines runs 1-2-3, from URL, returning HashableSents to pass to Pipeline

//1.
func conllBlobToChunks(conllBlob: String) -> [String] {
    // iterate over chars to find boundaries between sents in rawConll : find \n# seq
    // return  : 1 string = 1 sentence, in a list
    let char1 = "\n"
    let char2 = "#"
    let chars = Array(conllBlob)
    var conllSentenceChunks: [String] = []
    var current = ""

    var i = 0
    while i < chars.count {
        current.append(chars[i])
        if String(chars[i]) == char1, i + 1 < chars.count, String(chars[i + 1]) == char2 {
            conllSentenceChunks.append(current)
            current = ""
        }
        i += 1
    }
    if !current.isEmpty {
        conllSentenceChunks.append(current)
    }
    return conllSentenceChunks
}
//2.
func conllChunksToLines(conllChunks: [String]) -> [[String]]{
    var allSents: [[String]] = []
    for conllChunk in conllChunks{
        let currentSent = conllChunk.components(separatedBy: "\n")
        allSents.append(currentSent)
    }
    return allSents
}
//3.
func conllLinesToSents(conllLines: [[String]]) -> [Sentence]{
    
    var outputSentences: [Sentence] = []
    var currentSentId: String = ""
    let inputSents = conllLines // rename for similarity to model
    for inputSent in inputSents {
        var currentToks: [Token] = []
        for inputLine in inputSent {
            if inputLine.hasPrefix("#") {
                currentSentId = inputLine
            } else {
                let lineChunks = inputLine.split(separator: "\t")
                guard lineChunks.count > 1 else {
                    // Blank line (or malformed row) -- treat it as the end of
                    // the current sentence, package up what we've collected so
                    // far, and start fresh for the next one.
                    if !currentToks.isEmpty {
                        let newSentenceObject = Sentence(
                            sentID: currentSentId,
                            conllData: currentToks)
                        outputSentences.append(newSentenceObject)
                        currentToks = []
                        currentSentId = ""
                    }
                    continue
                }
                
                let newTok = Token(
                    tokid: Int(lineChunks[0]) ?? 0,
                    form: String(lineChunks[1]),
                    lemma: String(lineChunks[2]),
                    upos: String(lineChunks[3]),
                    xpos: String(lineChunks[4]),
                    feats: String(lineChunks[5]),
                    head: String(lineChunks[6]),
                    deprel: String(lineChunks[7]),
                    col8: String(lineChunks[8]),
                    col9: String(lineChunks[9])
                )
                
                currentToks.append(newTok)
            }
        }
        // Catch a final sentence that wasn't followed by a trailing blank line.
        if !currentToks.isEmpty {
            let newSentenceObject = Sentence(
                sentID: currentSentId,
                conllData: currentToks)
            outputSentences.append(newSentenceObject)
            currentToks = []
            currentSentId = ""
        }
    }
    return outputSentences
}
//4.
func makeConllLinesFromURL(inputURL: URL?) -> [[String]]{
//    var pretokenisedSentences: [[String]] = []
    // load source file as a string
//    let normalizedText: String = Bundle.main.loadText(inputFile, format: "conllu")
    guard let inputFile = inputURL else {
        print("guardlet failed")
        return []
    }
    print("guardlet passed")
    do {
        // Reads raw text directly from your sandbox URL :: step0
        let normalizedText = try String(contentsOf: inputFile, encoding: .utf8)
        print("normalizedText passed")
        // split the string into sentence chunks : step1
        let sentenceChunks: [String] = conllBlobToChunks(conllBlob: normalizedText)
        print("chunked")
        // split each chunk == sentence into its lines :: step2
        let hashableTokenLists: [[String]] = conllChunksToLines(conllChunks: sentenceChunks)
        print("Got file from conll")
        return hashableTokenLists
        
    } catch {
        print("Failed to read text from sandbox file: \(error)")
    }
    return []
}
//5.
func makeConllLinesFromFile(inputFile: String) -> [[String]]{
    
    // load source file as a string from bundle:: step0
    let normalizedText: String = Bundle.main.loadText(inputFile, format: "conllu")
    // split the string into sentence chunks :: step1
    let sentenceChunks: [String] = conllBlobToChunks(conllBlob: normalizedText)
    
    // split each chunk == sentence into its lines step2
    let pretokenisedSentences: [[String]] = conllChunksToLines(conllChunks: sentenceChunks)
    return pretokenisedSentences
}
//6.
func conllFileToHashableSentForPipeline(inputURL: URL?)  -> [HashableSentence]{
    guard let inputFile = inputURL else {
        print("guardlet failed")
        return []
    }
    var allSentences: [HashableSentence] = []
    let hashableTokenList: [[String]] = makeConllLinesFromURL(inputURL: inputFile)
    let intermedSents: [Sentence] = conllLinesToSents(conllLines: hashableTokenList)
    for sent in intermedSents{
        let TokSentVers = sent.hashableSentence
        allSentences.append(TokSentVers)
    }
    return allSentences
}
// MARK: - XML-conll parsing
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                              XML-conll parsing functions
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------

// parse XMLconllu with XML parser, including making instance of class
//1. parse xml-conll to get conll blob-pairs identical to CoNLL parsing
func xmlConllToIdBlobPairs(from url: URL?) -> [XMLConllElement] {
    guard let url = url else {
        print("xmlParsingFunc: no URL provided")
        return []
    }

    var results: [XMLConllElement] = []

    guard let parser = XMLParser(contentsOf: url) else {
        print("xmlParsingFunc: couldn't create XMLParser for \(url)")
        return results
    }

    let delegate = SParser()
    parser.delegate = delegate

    if parser.parse() {
        results = delegate.results
    } else {
        print("xmlParsingFunc: parse failed for \(url) — \(parser.parserError?.localizedDescription ?? "unknown error")")
    }

    return results
}
//2. call 1. then apply CoNLL parsing functions
func xmlConllFileToHashableSentForPipeline(inputURL: URL?)  -> [HashableSentence]{
    guard let inputFile = inputURL else {
        print("guardlet failed")
        return []
    }

    var allSentences: [HashableSentence] = []
    let conllBlobs: [XMLConllElement] = xmlConllToIdBlobPairs(from: inputURL)
    let linesFromBlobs:[[String]] = conllChunksToLines(conllChunks:conllBlobs.map { ($0.blob) })
    let intermedSents:[Sentence] = conllLinesToSents(conllLines: linesFromBlobs)
    for sent in intermedSents{
        let TokSentVers = sent.hashableSentence
        allSentences.append(TokSentVers)
    }

    return allSentences
}
// MARK: - XML parsing
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                  XML parsing functions
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//  1. xmlToHashableSents: does the XML parsing
//  2. xmlToHashableSentForPipeline : wrapper for 1.

//1. parse full XML to id:toklist ->> all sentences
func xmlToHashableSents(from url: URL?) -> [HashableSentence] {
    guard let url = url else {
        print("xmlParsingFunc: no URL provided")
        return []
    }

    var results: [HashableSentence] = []

    guard let parser = XMLParser(contentsOf: url) else {
        print("xmlParsingFunc: couldn't create XMLParser for \(url)")
        return results
    }
    
    let delegate = SWParser()
    parser.delegate = delegate

    if parser.parse() {
        results = delegate.results
    } else {
        print("xmlParsingFunc: parse failed for \(url) — \(parser.parserError?.localizedDescription ?? "unknown error")")
    }

    return results
}
//2. safe wrapper which calls xmlToHashableSents
func xmlToHashableSentForPipeline(inputURL: URL?)  -> [HashableSentence]{
    guard let inputFile = inputURL else {
        print("guardlet failed")
        return []
    }
    
    return  xmlToHashableSents(from: inputFile)
}



// MARK: - Agnostic output making
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                 Agnostic output making functions
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//1. convert sent to dumpable string for selected format
func makeExportContent(sentences: [Sentence], exportFormat: ExportFormat, safeHeaderAttribs: XmlHeaderAttribs) -> String{
    var returnString: String = ""
    switch exportFormat {
    case .conll, .conllTxt:
        returnString = sentences.generateExportText()
    case .conllTidy:
        returnString = sentences.generateExportTextTidy()
    case .xml:
        returnString = sentListToXML(
            sentences: sentences,
            selectedExportFormat: .xml,
            safeHeaderAttribs: safeHeaderAttribs
            )
    case .xmlConll:
        //make xml conll
        returnString = sentListToXML(
            sentences: sentences,
            selectedExportFormat: .xmlConll,
            safeHeaderAttribs: safeHeaderAttribs
            )
    }
    return returnString
}

// MARK: - XML making
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                  XML-making functions :: called in agnostic function
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//1. make safe header attributes
//2. Make XML string from list of sentences with output of 1, 2

//2.
func makeSafeXmlHeaderAttribs(
    xmlTitle: String,
    xmlAuthorName: String,
    selectedLanguage: Language,
    selectedTreebank: Language.Treebank,
    sourceFile: URL,
)-> XmlHeaderAttribs {
    
    let xmlSafeXMLAuthor = xmlAuthorName.xmlEscaped != "" ? xmlAuthorName.xmlEscaped : "author_unknown"
    let xmlSafeXMLTitle = xmlTitle.xmlEscaped != "" ? xmlTitle.xmlEscaped : "title"
    let xmlSafeLang = selectedLanguage.displayName.lowercased()
    let xmlsafeTreebank = selectedTreebank.short.xmlEscaped
    
    let formatter = DateFormatter()
    formatter.dateFormat = "y-MM-dd HH:mm"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let dateString = formatter.string(from:Date())
    let xmlsafeDate = dateString.xmlEscaped

    let xmlsafeSourceFile = sourceFile.path().xmlEscaped
    let runID = UUID().uuidString

    let outputStruct = XmlHeaderAttribs(
        xmlTitle: xmlSafeXMLTitle,
        xmlAuthorName: xmlSafeXMLAuthor,
        lang: xmlSafeLang,
        treebank: xmlsafeTreebank,
        taggingDate: xmlsafeDate,
        sourceFile: xmlsafeSourceFile,
        runID: runID,
    )
    return outputStruct
}

//3.
func sentListToXML(
    sentences: [Sentence],
    selectedExportFormat: ExportFormat,
    safeHeaderAttribs: XmlHeaderAttribs
) -> String {
    
    let xmlHeader = """
        <?xml version="1.0" encoding="utf-8"?>
          <TEI.2>
          <teiHeader>
            <fileDesc>
            <titleStmt>
            <title>\(safeHeaderAttribs.xmlTitle)</title>
            <author>\(safeHeaderAttribs.xmlAuthorName)</author>
            </titleStmt>
            <publicationStmt>
            <publisher />
            <date />
            <pubDate />
            </publicationStmt>
                <sourceDesc model="\(safeHeaderAttribs.lang.lowercased())" treebank="\(safeHeaderAttribs.treebank)" tagging_date="\(safeHeaderAttribs.taggingDate)" sourcefile="\(safeHeaderAttribs.sourceFile)" runID="\(safeHeaderAttribs.runID)">
                <p />
                </sourceDesc>
            </fileDesc>
            <profileDesc>
                <langUsage>
                <language ident="\(safeHeaderAttribs.lang)"/>
                </langUsage>
            <textDesc thema=\"\" type="unk" sub_genre=\"\" />
            </profileDesc>
        </teiHeader>
        <text>
        <body>
        <p>        
        """
    let xmlFooter = """
        </p>
        </body>
        </text>
        </TEI.2>
        """
    var outputStore: [String] = []
    outputStore.append(xmlHeader)
    for sentence in sentences {
        outputStore.append(sentence.makeXMLsent(exportFormat: selectedExportFormat))
    }
    outputStore.append(xmlFooter)
    
    return outputStore.joined(separator: "\n")
    
}
// MARK: - Writing
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                  Writing to file functions
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
// 1. Write stirng to location : as used in main version.
//  2. Run write coordinator :: run 3  with diff outputs then 4. No longer used
// 3. write string dump :: write string to named files on macOS AND iOS device ; No longer used
// 4. writtoFile ; No longer used


// write string to location
func saveFileToChosenLocation(exportContent: String, saveInputMetas: SaveInputMetas, runExplicit: Bool = false) -> RunMetas {
    // function called via UI to run main dump to file
    var savedURL: URL
    var exportStatusMessage: String
    guard let folderURL = saveInputMetas.targetFolderURL else {
        if runExplicit {
            print("Guard 292 fail")
        }
        return RunMetas(
            lang: saveInputMetas.lang.rawValue,
            sourceFileURL: saveInputMetas.inputURL,
            sourceFileName: saveInputMetas.displayName,
            outputFileName: saveInputMetas.saveName,
            treebank: saveInputMetas.treebank.short,
            exportFormat: saveInputMetas.exportFormat,
            unread: true,
            savedURL: nil,
            message: "Guard failure in save file to chosen location",
            safeHeaderAttribs: saveInputMetas.safeHeaderAttribs
        )
        
    }
    if runExplicit {
        print("Guard 292 passed")
    }
    do {
        savedURL = try ExporterService.exportDataToFile(
            exportContent: exportContent,
            customName: "\(saveInputMetas.saveName)_\(saveInputMetas.treebank.short)_\(saveInputMetas.exportFormat.rawValue)",
            targetFolderURL: folderURL,
            exportFormat: saveInputMetas.exportFormat
        )
        exportStatusMessage = "Successfully exported to \(savedURL.lastPathComponent)"
        if runExplicit { print(exportStatusMessage) }
        
        return RunMetas(
            lang: saveInputMetas.lang.rawValue,
            sourceFileURL: saveInputMetas.inputURL,
            sourceFileName: saveInputMetas.displayName,
            outputFileName: saveInputMetas.saveName,
            treebank: saveInputMetas.treebank.short,
            exportFormat: saveInputMetas.exportFormat,
            unread: true,
            savedURL: savedURL,
            message: exportStatusMessage,
            safeHeaderAttribs: saveInputMetas.safeHeaderAttribs
        )
        
        
        
    } catch {
        exportStatusMessage = "Export failed: \(error.localizedDescription)"
        if runExplicit { print(exportStatusMessage) }
        
        return RunMetas(
            lang: saveInputMetas.lang.rawValue,
            sourceFileURL: saveInputMetas.inputURL,
            sourceFileName: saveInputMetas.displayName,
            outputFileName: saveInputMetas.saveName,
            treebank: saveInputMetas.treebank.short,
            exportFormat: saveInputMetas.exportFormat,
            unread:  true,
            savedURL: nil,
            message: exportStatusMessage,
            safeHeaderAttribs: saveInputMetas.safeHeaderAttribs
        )

    }
}

func runWriteCoordinator(lines: [String], rawLines: [String]) throws {
    try writeStringDump(lines)
    try writeStringDump(rawLines)

    let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let outputPath = docsDir.appendingPathComponent("output.conllu").path
    try writeToFile(rawLines.joined(separator: "\n"), outputPath)
}

func writeStringDump(_ lines: [String]) throws -> URL {
    // write 2 versions of output string, with FileManager and to specified dev folder
    let content = lines.joined(separator: "\n")
    let fileName = "string_dump_\(Int(Date().timeIntervalSince1970 * 1_000_000_000)).conllu"
    
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let fileURL = documentsURL.appendingPathComponent(fileName)
    let newUrl: URL = URL(fileURLWithPath: "/Volumes/Kappa/Xcode/parses/\(fileName)")
    try content.write(to: newUrl, atomically: true, encoding: .utf8)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
    print("Saved CoNLL dump to: \(fileURL.path)")

    return fileURL
}
 
func writeToFile(_ content: String, _ path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
    print("Wrote file to: \(url)")

}
// MARK: - Printing
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                  Print to console : for dev
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//1. print JSON errror info to console
// 2. Print from print to conllSents to console, specific macOS file
// 3. print conll form of sentences on output, before calling mainActor
//1.
func printJSONError(_ error: Error) {
    let nsError = error as NSError
    print("Domain:", nsError.domain)
    print("Code:", nsError.code)
    if let debug = nsError.userInfo["NSDebugDescription"] {
        print("Debug:", debug)
    }
    if let path = nsError.userInfo["NSJSONSerializationErrorIndex"] {
        print("Index:", path)
    }
}
//2
func printFromConllSents(outsents: [Sentence]) throws -> URL{
    
    let mySents: [Sentence] = outsents
    let fileName = "string_dump_\(Int(Date().timeIntervalSince1970 * 1_000_000_000))_special.conllu"
    let newUrl: URL = URL(fileURLWithPath: "/Volumes/Kappa/Xcode/parses/\(fileName)")
    
    var myLines: [String] = []
    var atStart: Bool = true
    for sent in mySents {
        if atStart {
            atStart = false
            let pattern =  #"^\n{2}"#
            var firstSent = sent.conll
            print(firstSent.count)
            if let range = firstSent.range(of: pattern, options: .regularExpression) {
                firstSent.removeSubrange(range)
            }
            myLines.append(firstSent)
            print("Appended length = \(firstSent.count)")
        } else {
            myLines.append(sent.conll)
        }
    }
    for sent in mySents {
        myLines.append(sent.conllTidy)
    }
    
    let content = myLines.joined(separator: "")
    try content.write(to: newUrl, atomically: true, encoding: .utf8)
    print("Saved CoNLL dump to: \(newUrl.path)")
    
    return newUrl
    
}

//3
func dumpDetailsForRunExplicit(runExplicit: Bool, outSents: [Sentence], targetFolderURL: URL?, fileName: String) {
    // print conll lines to terminal
    if runExplicit {
        print("Printing conllRaw")
        for sentence in outSents {
            print(sentence.conll)
        }
        if let printPath = targetFolderURL?.path(){
            print(printPath)
        } else {
            print("Problem with print path from URL 274")
        }
        print("output name = \(fileName)")
        print("Main actor done, running function 277")
    }
    
    
    
    //no returns
}

//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                  encapsulation of run inputs, outputs
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------

func makeTidyRunOutput(outSents: [Sentence], saveInputMetas: SaveInputMetas, safeHeaderAttribs: XmlHeaderAttribs) -> RunOutput {
    
    let exportContent = makeExportContent(
        sentences: outSents,
        exportFormat: saveInputMetas.exportFormat,
        safeHeaderAttribs: saveInputMetas.safeHeaderAttribs
    )
    
    let runData: RunData = RunData(
        sents: outSents,
        exportContent: exportContent
    )
    
    let runMetas = saveFileToChosenLocation(
        exportContent: exportContent,
        saveInputMetas: saveInputMetas
    )
    
    let runOutput = RunOutput(
        runData: runData,
        runMetas: runMetas
    )
 
    return runOutput
}


//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                  end of main functions; experimental below
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
// MARK: - Other
struct NLReturn:  Identifiable{
    var id = UUID()
    let tokRange: String
    let rawTag: String
}

struct NLParseReturn: Identifiable {
    var id = UUID()
    let tag: String
    let nlReturn: [NLReturn]
}

struct NLParseResults: Identifiable{
    var id = UUID()
    let posReturn: NLParseReturn
    let lemmaReturn: NLParseReturn
}
func getNLTags(text: String) -> NLParseResults{
    // get POS tags with inbuilt tagset, tagger -> No diff btw SCONJ, CCONJ, no proper noun
    var posTags: [NLReturn] = []
    var lemmas: [NLReturn] = []
    
    let tagger = NLTagger(tagSchemes: [ .lemma, .lexicalClass])
    let options: NLTagger.Options = [ .omitWhitespace]
    tagger.string = text

    tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
        if let tag = tag {
            posTags.append(NLReturn(tokRange: String(text[tokenRange]), rawTag: tag.rawValue))
            print("Token: \(String(text[tokenRange])) : tag: \(tag.rawValue)")
        }
        return true // signal to enumerator to keep going with enumeration
    }
    tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma, options: options) {tag, tokenRange in
        if let tag = tag {
            lemmas.append(NLReturn(tokRange: String(text[tokenRange]), rawTag: tag.rawValue))
        }
        return true
    }
    let posReturn: NLParseReturn = NLParseReturn(tag: "pos", nlReturn: posTags)
    let lemmaReturn: NLParseReturn = NLParseReturn(tag: "lemma", nlReturn: lemmas)
    return NLParseResults(posReturn: posReturn, lemmaReturn: lemmaReturn)
}
//MARK: functions not called

//MARK: sentencisation
//func untokenisedInputToSents(text: [String], languageCode: Language) throws -> [[String]]{
//    var returnItem: [[String]] = []
//    let pipeline = try UDPipeline(languageCode: languageCode.rawValue, treebank: "gsd")
//    for (_, sent) in text.enumerated(){
//        let currentSent = try  pipeline.tokenize(sent)
//        for chunk in currentSent{
//            returnItem.append(chunk.tokens)
//        }
//    }
//    return returnItem
//}

//MARK: tokenisation
//func applyNaiveTokenisationToString(inputText: String) -> [String]{
//    return inputText.components(separatedBy: " ")
//}
//func getTokens(languageCode: String, method: TokenisationMethod, inputFile: String = "", targetString: String = "") -> [[String]]{
//    var internalList: [[String]] = []
//    switch method {
//    case .conll:
//        print("Use conll input as tokenisation")
//        return makeConllLinesFromFile(inputFile: inputFile)
//
//    case .retokenise:
//        print("Use tokeniser to predict")
//        do {
//            let pipeline = try UDPipeline(languageCode: languageCode, treebank: "gsd")
//            let hashableSentences = try pipeline.tokenize(targetString)
//            print("printing chunks")
//            print(hashableSentences)
//            print("End chunks")
//
//            for sent in hashableSentences{
//                internalList.append(sent.tokens)
//            }
//        }
//        catch {
//            let errorDesc = error.localizedDescription
//            print("error in get tokens function with pipeline")
//            print(errorDesc)
//        }
//        return internalList
//    }
//}
//
//
//func predictedSentsToTokenisedSents(input: [[String]]) -> [TokenisedSentence]{
//    var returnItem: [TokenisedSentence] = []
//    var count: Int = 0
//    print(input)
//
//    //    actions
//    for predictedSent in input{
//        count += 1
//        let tidyToks = predictedSent
//        let newSent = HashableSentence(id: String(count), tokens: tidyToks)
//        returnItem.append(newSent)
//    }
//    return returnItem
//}
//

