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


//MARK: loading + parsing conll
    
//MARK: conlltools:: this is good for inspecting the tokenisation, and parsing if any, but it's not the seq of toks that the parser needs
//TODO: func that returns a list of tokenised sentences
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


func makeConllLinesFromFile(inputFile: String) -> [[String]]{
    
    // load source file as a string from bundle:: step0
    let normalizedText: String = Bundle.main.loadText(inputFile, format: "conllu")
    // split the string into sentence chunks :: step1
    let sentenceChunks: [String] = conllBlobToChunks(conllBlob: normalizedText)
    
    // split each chunk == sentence into its lines step2
    let pretokenisedSentences: [[String]] = conllChunksToLines(conllChunks: sentenceChunks)
    return pretokenisedSentences
}

//this removes emptysents made bt makeConllLinesFromFile
func makeTokenisedSentsFromFile(inputSents: [[String]]) -> [HashableSentence]{
    // ge tinput from getPretokenised
    var outputTokSents: [HashableSentence] = []
    var currentSentId: String = ""
    for inputSent in inputSents {
        var currentToks: [String] = []
        for inputLine in inputSent {
            if inputLine.hasPrefix("#") {
                currentSentId = inputLine
            } else {
                let fields = inputLine.split(separator: "\t")
                guard fields.count > 1 else {
                    // Blank/malformed row --> end of sentence
                    if !currentToks.isEmpty {
                        outputTokSents.append(HashableSentence(id: currentSentId, tokens: currentToks))
                        currentToks = []
                        currentSentId = ""
                    }
                    continue
                }
                currentToks.append(String(fields[1]))
            }
        }
        // Catch a final sentence that wasn't followed by a trailing blank line.
        if !currentToks.isEmpty {
            outputTokSents.append(HashableSentence(id: currentSentId, tokens: currentToks))
        }
    }
    return outputTokSents
}


// MARK:  functions to parse existing .conll documents
/// step1 is in Bundle.main
/// step2 :: get sentences
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

/// step3:
//// split sentence chunk into lines
func conllChunksToLines(conllChunks: [String]) -> [[String]]{
    var allSents: [[String]] = []
    for conllChunk in conllChunks{
        let currentSent = conllChunk.components(separatedBy: "\n")
        allSents.append(currentSent)
    }
    return allSents
}

//// step4 :
// make [ConllSent] from [[String]]
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

//MARK: making XML
//make xml from ConllSents - part1
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

//make xml from ConllSents- get xml safe values for attribs
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

//MARK: writing to file
// write string to location
func saveFileToChosenLocation(exportContent: String, saveName: String, targetFolderURL: URL?, exportFormat: ExportFormat, treebank: Language.Treebank, runExplicit: Bool = false) -> SaveReport {
    // function called via UI to run main dump to file
    var savedURL: URL
    var exportStatusMessage: String
    guard let folderURL = targetFolderURL else {
        if runExplicit {
            print("Guard 292 fail")
        }
        return SaveReport(savedURL: nil, message: "Guard failure")
    }
    if runExplicit {
        print("Guard 292 passed")
    }
    do {
        savedURL = try ExporterService.exportDataToFile(
            exportContent: exportContent,
            customName: "\(saveName)_\(treebank.short)_\(exportFormat.rawValue)",
            targetFolderURL: folderURL,
            exportFormat: exportFormat
        )
        exportStatusMessage = "Successfully exported to \(savedURL.lastPathComponent)"
        if runExplicit { print(exportStatusMessage) }
        return SaveReport(savedURL: savedURL, message: exportStatusMessage)
    } catch {
        exportStatusMessage = "Export failed: \(error.localizedDescription)"
        if runExplicit { print(exportStatusMessage) }
        return SaveReport(savedURL: nil, message: exportStatusMessage)

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
//MARK: printing to console::

// print info on JSON error
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


// print to conllSents to console
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


//MARK: functions not called
//func runConllFileParserPipe(pretokenisedSentences: [[String]]) -> [ConllSent]{
//    let conllSents: [ConllSent] = conllLinesToSents(conllLines: pretokenisedSentences)
//    return conllSents
//}
//
//func getSentsForPipelineFromPretokConll(inputFile: String) ->[TokenisedSentence]{
//    let pretokenisedSentences = makeConllLinesFromFile(inputFile: inputFile)
//    let outputSentences  = makeTokenisedSentsFromFile(inputSents: pretokenisedSentences)
//    return outputSentences
//}

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

//func xmlFileToHashableSentForPipeline(inputURL: URL?)  -> [HashableSentence]{
//    guard let inputFile = inputURL else {
//        print("guardlet failed")
//        return []
//    }
//    var allSentences: [HashableSentence] = []
//
//    return allSentences
//
//}

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


// parse XMLconllu with XML parser, including making instance of class
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


//parse full XML to id:toklist ->> all sentences
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

func xmlToHashableSentForPipeline(inputURL: URL?)  -> [HashableSentence]{
    guard let inputFile = inputURL else {
        print("guardlet failed")
        return []
    }
    
    return  xmlToHashableSents(from: inputFile)
}


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
