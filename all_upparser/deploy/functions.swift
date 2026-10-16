//
//  functions.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
// functs for general use

import CoreML
import Foundation
import NaturalLanguage
import SwiftUI
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------


//MARK : helper functions: get data from file, and specialloader from inside bundle
//  1. read from file :: std read file via URL, for use outside bundle. URL -> String
//  2. load textFromBundledFile : read file via name from inside bundle. Filename -> String
//  3. Detect lang in filename. regex to find lang in inputfilename for view
//  4. test instantiate pipeline.
//  5. dump scalars : can be used to dump logits
//1
func readFromFile(inputURL: URL?) throws -> String {
    guard let inputFile = inputURL else { throw ParseProcessingError.missingURL}
    do {
        let returnString = try String(contentsOf: inputFile, encoding: .utf8)
        return returnString
    } catch {
        return error.localizedDescription
    }
}
//2.
func loadTextFromBundledFile(inputFile: String, thisExtension: String) throws -> String{
    do {
        let normalizedText: String = try Bundle.main.loadText(inputFile, format: thisExtension)
        return normalizedText
    } catch {
        return ParseProcessingError.fileLoadError.localizedDescription
    }
}

//3
func detectLangInFilename(inputURL: URL?)-> Language?{
    // actions
    guard let urlExists = inputURL else { return nil }
    let targetPartOfString = urlExists.lastPathComponent.lowercased()
    var langGuess: Language? = nil
    var matchCount: Int = 0
    let myMaps: [RegexLangPatternToLangMap] = [
        RegexLangPatternToLangMap(string: #"[_\.]fr|^fr_"#, langValue: .FR),
        RegexLangPatternToLangMap(string: #"[_\.]fro|^fro_"#, langValue: .FRO),
        RegexLangPatternToLangMap(string: #"[_\.]frm|^frm_"#, langValue: .FRM),
        RegexLangPatternToLangMap(string: #"[_\.]de|^de_"#, langValue: .DE),
        RegexLangPatternToLangMap(string: #"[_\.]en|^en_"#, langValue: .EN),
        RegexLangPatternToLangMap(string: #"[_\.]ang|^ang_"#, langValue: .ANG),
    ]
    for thisItem in myMaps {
        if targetPartOfString.contains(thisItem.asRegex){
            langGuess = thisItem.langValue
            matchCount += 1
            print("\(langGuess?.rawValue ?? "UNK") for \(targetPartOfString)")
        }
    }
    if matchCount > 0 {
        return langGuess
    } else {
        return nil
    }
}
//4
func testInstantiatePipeline(myConfig: TaggerConfig)   -> String {
    // test instantiation of pipeline class based on params chosen
    var outputString: String = ""
    
    Task{
        do {
            let _ = try UDPipeline(myConfig: myConfig)
            await MainActor.run {
                outputString = "Success"
            }
        } catch {
            await MainActor.run {
                outputString = "Fail : \(error.localizedDescription)"
            }
        }
    }
    return outputString
}
//5
func dumpScalars(_ text: String, maxChars: Int = 50) {
    // called in runTest() function
    for scalar in text.unicodeScalars.prefix(maxChars) {
        print("\(scalar) -> \(scalar.value)")
    }
}

////3.
func markupTokenisationInSent(hashableSent: HashableSentence) -> AttributedString{
        
        var result = AttributedString()
        for (index, word) in hashableSent.tokens.enumerated() {
            result.append(AttributedString(word))
            if index < hashableSent.tokens.count - 1 {
                var separator = AttributedString("/")
                separator.foregroundColor = .red // Make separator red
                separator.font = .system(size: 17, weight: .bold)
                result.append(separator)
            }
        }
    return result
}

func makeFilename() -> String {
    return String(UUID().uuidString.prefix(6))
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
func _conllBlobToChunks(conllBlob: String) -> [String] {
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
func _conllChunksToLines(conllChunks: [String]) -> [[String]]{
    var allSents: [[String]] = []
    for conllChunk in conllChunks{
        let currentSent = conllChunk.components(separatedBy: "\n")
        allSents.append(currentSent)
    }
    return allSents
}
//3.
func _conllLinesToSents(inputURL: URL, conllLines: [[String]]) throws -> [Sentence]{
    
    var outputSentences: [Sentence] = []
    var currentSentId: String = ""
    let inputSents = conllLines // rename for similarity to model
    for (sentNum, inputSent) in inputSents.enumerated() {
        var currentToks: [Token] = []
        var currentMetas: [String] = []
        for (lineNum, inputLine) in inputSent.enumerated() {
            // deal with metas
            if inputLine.hasPrefix("#"){
                if lineNum == 0 {
                    currentSentId = String(inputLine)
                } else {
                    currentMetas.append(String(inputLine))
                }
            } else {
                // deal with all non-meta
                let lineChunks = inputLine.split(separator: "\t", omittingEmptySubsequences: true)
                if lineChunks.count == 0 {
                    // Allow 0 or 1 chunk (empty/malformed line that resets state)
                    if !currentToks.isEmpty {
                        let newSentenceObject = Sentence(
                            sentID: currentSentId,
                            conllData: currentToks,
                            conllMetas: currentMetas
                        )
                        outputSentences.append(newSentenceObject)
                        currentToks = []
                        currentSentId = ""
                    }
                continue
                }

                guard lineChunks.count == 10 else {
                    let errorstring = lineChunks.count == 0 ?  "no chunks " :lineChunks.joined(separator: "<TAB>")
                    throw ParseProcessingError.conllParsingError(
                        line: String("Sent:\(sentNum + 1) line \(lineNum + 1) :: \(errorstring)"),
                        filename: String(inputURL.lastPathComponent))

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
        
        if !currentToks.isEmpty {
            let newSentenceObject = Sentence(
                sentID: currentSentId,
                conllData: currentToks,
                conllMetas: currentMetas
            )
            outputSentences.append(newSentenceObject)
        }
    }
    return outputSentences
}
//4.
func _makeConllLinesFromURL(inputURL: URL?) throws -> [[String]]{
    guard let inputURL else {
            throw ParseProcessingError.missingURL
    }
    do {
        let normalizedText = try readFromFile(inputURL: inputURL)
        guard  !normalizedText.isEmpty else {
            throw ParseProcessingError.readFromSandboxError
        }
        
        let sentenceChunks: [String] = _conllBlobToChunks(conllBlob: normalizedText)
        guard !sentenceChunks.isEmpty else {
            throw ParseProcessingError.conllLineIdentificationError
        }

        let hashableTokenLists: [[String]] = _conllChunksToLines(conllChunks: sentenceChunks)
        guard !hashableTokenLists.isEmpty else {
            throw ParseProcessingError.conllChunkToLineError
        }
        return hashableTokenLists
        
    } catch {
        throw ParseProcessingError.makeConllLinesFromURLError
    }
}

//6.
func conllFileToHashableSentForPipeline(inputURL: URL?) throws -> [HashableSentence]{
    guard let inputFile = inputURL else {
        throw ParseProcessingError.missingURL
    }
    var allSentences: [HashableSentence] = []
    let hashableTokenList: [[String]] = try _makeConllLinesFromURL(inputURL: inputFile) // funct4, calls 1,2
    let intermedSents: [Sentence] = try _conllLinesToSents(inputURL: inputFile, conllLines: hashableTokenList)// func3
    
    for (sentNum,sent) in intermedSents.enumerated(){
        let TokSentVers = sent.hashableSentence
        print("\(sentNum) :: tokCount = \(sent.conllData.count)")
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

// parse XMLconllu with XML parser, including making instance of class :: uses different parser with different output 
//1. parse xml-conll to get conll blob-pairs identical to CoNLL parsing
func _xmlConllToIdBlobPairs(from url: URL?) throws -> [XMLConllElement] {
    guard let url = url else {
        throw ParseProcessingError.missingURL
    }

    guard let parser = XMLParser(contentsOf: url) else {
        throw ParseProcessingError.parserCreationError(file: url)
    }

    let delegate = SParser()
    parser.delegate = delegate

    let success = parser.parse()

    if !success{
        if let parserError = parser.parserError{
            throw parserError
        } else {
            throw ParseProcessingError.xmlParserFailure(line: 0, reason:"Unknown XML parsing error")
        }
    }
    return delegate.results
}
//2. call 1. then apply CoNLL parsing functions
func xmlConllFileToHashableSentForPipeline(inputURL: URL?) throws -> [HashableSentence]{
    guard let inputURL else {
        throw ParseProcessingError.missingURL
    }

    var allSentences: [HashableSentence] = []
    let conllBlobs: [XMLConllElement] = try _xmlConllToIdBlobPairs(from: inputURL)
    let linesFromBlobs:[[String]] = _conllChunksToLines(conllChunks:conllBlobs.map { ($0.blob) })
    let intermedSents:[Sentence] = try _conllLinesToSents(inputURL: inputURL, conllLines: linesFromBlobs)
    allSentences.append(contentsOf: intermedSents.map {$0.hashableSentence} )
    
    return allSentences
}

// MARK: - XML parsing
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                  XML parsing functions
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
// 1 function with SWParser, delegate, for std xml -> hashable sent. XMLConll needs 2 steps to conllise
func xmlToHashableSentForPipeline(inputURL: URL?) throws  -> [HashableSentence]{
    guard let inputURL else {
        throw ParseProcessingError.missingURL
    }

    guard let parser = XMLParser(contentsOf: inputURL) else {
        throw ParseProcessingError.parserCreationError(file: inputURL)
    }
    
    let delegate = SWParser()
    parser.delegate = delegate
    let success = parser.parse()

    if !success{
        if let parserError = parser.parserError{
            throw parserError
        } else {
            throw ParseProcessingError.xmlParserFailure(line: 0, reason:"Unknown XML parsing error")
        }
    }
    return delegate.results

}
// MARK: - TXT parsing
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                  TXT parsing functions
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//  1. blob to sents: sentencise based on custom regex Rules 					:: String -> [String] w regex
//  2. getSentencesWithNL: sentencise with inbuilt NLTokeniser					:: String -> [String] w nlSentencizer
//  2b/ applySentencizingMethodToStirng                                         :: String -> [String] method :  encapsulates 1, 2
//  3. textFileToSentStrings : read in TXT file and use 1 or 2 to sentencise	:: File -> String -> [String] : escapsulates load, 2b

//  4. sentStringToHashableSents: use pipeline or func5 to tokenise				:: [String] -> [Hashable] w choose
//  5. getTokenisedSents: use inbuilt NL tagger to tokenise						::[String] -> [Hashable] w pipeline
//  6. textFileToHashableSets : use func3 to sentencise then 4 to tokenise      :: File -> Hashable

//1
func _blobToSents(blob: String,  myConfig: TaggerConfig) -> [String]{
//        var holding: [String] = []
        // break on \.\n\n
        var test2: String
        // double linebreak to sent boundary
        
    	test2 = blob.replacing(RegexStash.blobToSents.regex1){ match in "_EOS_" }
        test2 = test2.replacing(RegexStash.blobToSents.regex2){ match in "_EOS_" }
        test2 = test2.replacing(RegexStash.blobToSents.regex3){match in
            let matchedText = match[1].substring ?? "_ERROR_"
            let returnstring = "._EOS_\(matchedText)"
            return returnstring
        }
        test2 = test2.replacing(RegexStash.blobToSents.overzealousPattern){ match in "U.S. " }
        
        let chunks = test2.components(separatedBy: "_EOS_")

    let validChunks = chunks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if myConfig.parsingConfig.runExplicit{
        for (num, chunk) in validChunks.enumerated() {
            print("\(num) :: \(chunk)")
        }
        let printArray = Array(repeating: "#", count: 133).joined(separator: "")
        print(printArray)
    }
        return validChunks
    }
//2

func _getSentencesWithNL(text: String, myConfig: TaggerConfig)-> [String]{
    let tokenizer = NLTokenizer(unit: .sentence) // unit == sentences ::>> SENTENCISATION
    let nlLang: NLLanguage

    switch myConfig.parsingConfig.selectedLanguage {
            case .ANG, .EN: nlLang = NLLanguage.english
            case .FR,.FRM, .FRO: nlLang = NLLanguage.french
            case .DE: nlLang = NLLanguage.german
        }
    if myConfig.parsingConfig.runExplicit{
        print("sentencizing with nlSentencizer->192")
    }
        tokenizer.setLanguage(nlLang)
        tokenizer.string = text
        var sentencesOut: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex){range, _ in
            let itemToAppend = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !itemToAppend.isEmpty  {
                sentencesOut.append(itemToAppend)}
            return true
        }
    if myConfig.parsingConfig.runExplicit{
        for (num, chunk) in sentencesOut.enumerated() {
            print("\(num) :: \(chunk)")
        }
        
        let printArray = Array(repeating: "#", count: 133).joined(separator: "")
        print(printArray)
    }
        return sentencesOut
    }
//2b
func _applySentencizingMethodToString(normalizedText: String,  myConfig: TaggerConfig) throws -> [String] {
    
    var sentencesAsStrings: [String] = []
    switch myConfig.parsingConfig.sentencizingMethod {
        // use NL or custom logic to get sentences as strings from an input blob
    case .nlSentencizer:
        // get sentences from input blob
        if myConfig.parsingConfig.runExplicit{
            print("sentencizing with nlSentencizer")
        }
        sentencesAsStrings = _getSentencesWithNL(text: normalizedText, myConfig: myConfig)
        
    case .eosMark:
        if myConfig.parsingConfig.runExplicit{
            print("finish code from EOS marking wiht regex")
        }
        
    case .custom:
        if myConfig.parsingConfig.runExplicit{
            print("sentencizing with custom")
        }
        sentencesAsStrings = _blobToSents(blob: normalizedText, myConfig: myConfig)
        
    case .naive:
        if myConfig.parsingConfig.runExplicit{
            print("Using naive sentencizer based on toks")
        }
        
        do {
            let toksAsStrings = try applyNaiveTokenisation(language: myConfig.parsingConfig.selectedLanguage, myString: normalizedText)
            let tempTokList: [TempToken] = toksAsStrings.map {$0.asTempToken}
            
            var outputSents: [String] = []
            var currentSent: [String] = []
            let list1 = [".", "?", "!"]
            for (_, tok) in tempTokList.enumerated(){
                
                
                // 1. Check if it ends with any item in list1
                if let _ = list1.first(where: { tok.form.hasSuffix($0) }) {
                    currentSent.append(tok.form)
                    outputSents.append(currentSent.joined(separator: " "))
                    currentSent = []
                    
                }
                // 2. Check if it ends with an actual newline (\n, NOT "\\n")
                else if tok.form.hasSuffix("\n") {
                    // Strip the trailing newline safely
                    currentSent.append(String(tok.form.dropLast()))
                    outputSents.append(currentSent.joined(separator: " "))
                    currentSent = []
                }
                // 3. Check if it starts with an actual newline (\n)
                else if tok.form.hasPrefix("\n") {
                    // Strip the leading newline safely
                    currentSent.append(String(tok.form.dropFirst()))
                    outputSents.append(currentSent.joined(separator: " "))
                    currentSent = []
                }
                // 4. Default fallback action
                else {
                    currentSent.append(tok.form)
                }
            }
            
            if currentSent != []{
                outputSents.append(currentSent.joined(separator: " "))
            }
            sentencesAsStrings = outputSents//filter here ???
            return sentencesAsStrings
        } catch {
            throw error
        }
    }
    return sentencesAsStrings
    
}

//3
func textFileToSentStrings(myConfig: TaggerConfig, tokenizerPipeline: UDPipeline) throws -> [String]{
    guard let _ = myConfig.inputConfig.selectedInputFile else {
        print("guard let failed loading form file")
        return []
    }
    if myConfig.parsingConfig.runExplicit{
        print("running text file to sent strings function")
    }
    let inputString = try readFromFile(inputURL: myConfig.inputConfig.selectedInputFile)
    guard !inputString.isEmpty else {
        throw ParseProcessingError.fileLoadError
    }
    do {
        let normalizedText = inputString.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
        if myConfig.parsingConfig.runExplicit{
            print("first let success")
        }
        let sentencesAsString = try _applySentencizingMethodToString(normalizedText: normalizedText, myConfig: myConfig)
        return sentencesAsString
    }
    
}

func desentenciseAndResentencise(sentsToDiscard: [HashableSentence], myConfig: TaggerConfig) throws -> [String]{
    
    let initialString = (sentsToDiscard.map {$0.detokenised}).joined(separator: " ")
    let normalizedText = initialString.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
    let resentencizerOutputStrings = try _applySentencizingMethodToString(normalizedText: normalizedText, myConfig: myConfig)

    return resentencizerOutputStrings
}



func retokenisationEncapsulator(myConfig: TaggerConfig, pipeline: UDPipeline, taggingInProgress: Binding<Bool>) throws -> [HashableSentence]{
    
    var sentencesAsStrings: [String] = []
    
    if myConfig.parsingConfig.runResentenciser {
        sentencesAsStrings = myConfig.inputData.resentencizerOutputStrings
    } else {
        for sent in myConfig.inputData.allSentences{
            sentencesAsStrings.append(sent.detokenised)
        }
    }

    let retokenisedSents = try stringSentsToHashableSents(
        myConfig: myConfig,
        sents: sentencesAsStrings,
        pipeline: pipeline,
    )
    
    guard !retokenisedSents.isEmpty else {
        taggingInProgress.wrappedValue = false
        throw ParseProcessingError.retokenisationError
    }

    return retokenisedSents
}
func ingestSentEncapsulator(
    myConfig: TaggerConfig,
    pipeline: UDPipeline
) throws -> [HashableSentence] {
    
    var allSentences: [HashableSentence] = []
    switch myConfig.inputConfig.inputFileType {
    case .conll:
        // resentencise internally in this function if set
        allSentences = try conllFileToHashableSentForPipeline(
            inputURL: myConfig.inputConfig.selectedInputFile
        )
    case .manual:
        let myBuiltSents = myConfig.inputData.builtSents
        allSentences = myBuiltSents.compactMap {$0.toHashableSent(tempToks: $0.tempToks) }
        
    case .xml:
        // resentencise internally in this function if set
        allSentences = try xmlToHashableSentForPipeline(
            inputURL: myConfig.inputConfig.selectedInputFile
        )
    case .xmlConll:
        // resentencise internally in this function if set
        allSentences = try xmlConllFileToHashableSentForPipeline(
            inputURL: myConfig.inputConfig.selectedInputFile
        )
    case .txt:
        // this uses NaturalLanguage tagger as a sentenciser or custom ruleset (not yet written to sentencize blobs of text
        
        allSentences = try textFileToHashableSents(myConfig: myConfig, pipeline: pipeline)

        if myConfig.parsingConfig.runExplicit{
            print("Mode a: \(allSentences.count) sents ")
        }
        
    }
    return allSentences
}

//1.
func applyNaiveTokenisation(language: Language, myString: String) throws -> [String]{
    guard ![.DE, .ANG].contains(language) else {
        throw ParseProcessingError.languageMethodConflict(language: language)
    }
    
    let input: String = myString
//    var outputStrings: [String] = []
    var step1: [Substring] = []
    if [.FR, .FRO, .FRM].contains(language) {
        
        let replacements: [String: String] = [
            "jourd'hui": "jourdhui",
            "rud'homm": "rudhomm",
            "'":"' "
        ]
        let unreplacements: [String: String] = [
            "jourdhui": "jourd'hui",
            "rudhomm": "rud'homm"
        ]

        let unreplacePattern = unreplacements.keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let regexUnreplace = try! Regex(unreplacePattern)

        let literalPattern = replacements.keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let fullPattern = "(\(literalPattern))|([.?!]$)|([,;:])"
        let regex = try! Regex(fullPattern)

        
        let frResult = myString.replacing(regex) { match in
            let matchedText = String(match.0)
            if matchedText == "." && match.0 == myString.suffix(1) {
                return " ."
            }
            if let replacement = replacements[matchedText] {
                return replacement
            }
            // must be punctuation needing a leading space
            return " " + matchedText
        }
        var preSplit = frResult.replacingOccurrences(of: "  ", with: " ")
        
        preSplit = preSplit.replacing(regexUnreplace) { match in
            unreplacements[String(match.0)] ?? String(match.0)
        }
        step1 = preSplit.split(whereSeparator: { $0 == " " })
    }
    
    if language == .EN {
        step1 = input.split(whereSeparator: { $0 == " "})
    }

    return step1.map {String($0)}
}


//4
func stringSentsToHashableSents(myConfig: TaggerConfig, sents: [String], pipeline: UDPipeline) throws -> [HashableSentence]{

    var internalSentList: [HashableSentence] = []
    switch myConfig.parsingConfig.tokenizingMethod {
        
    case .custom, .manual, .skip:
        if myConfig.parsingConfig.runExplicit{
            print("using custom rules:: need to get Swift version of rules……")
        }
        break

    case .nltokeniser:
        if myConfig.parsingConfig.runExplicit{
            print("calling getTokSents @ line 85")
            print("nltokeniser")
        }
        internalSentList = _getTokenisedSentences(sents: sents, myConfig: myConfig)
        
    case .trained:
        // retokenize everything with model
        // MARK: can change this IN to be testSentences
        //    let pipeline = try UDPipeline(languageCode: languageCode.rawValue, treebank: "gsd")

        if myConfig.parsingConfig.runExplicit{
            print("sentencizing with trained")
        }
        for sentence in sents {
            internalSentList.append(contentsOf: try pipeline.tokenize(sentence))
        }
    }
    return internalSentList
}


//5 -- this is a tokenisation function :: tokenise wiht NL
func _getTokenisedSentences(sents: [String], myConfig: TaggerConfig) -> [HashableSentence]{
        let tagger = NLTagger(tagSchemes: [.tokenType]) // unit == tokenType ::>> TOKENISATION
        let nlLang: NLLanguage
        switch myConfig.parsingConfig.selectedLanguage {
        case .ANG, .EN: nlLang = NLLanguage.english
        case .FR, .FRM, .FRO: nlLang = NLLanguage.french
        case .DE: nlLang = NLLanguage.german
        }
        var sentsOut: [HashableSentence] = []
    
        for (snum, sent) in sents.enumerated() {
            tagger.string = sent
            let myRange = sent.startIndex..<sent.endIndex
            tagger.setLanguage(nlLang, range: myRange)
            
            var currentToks: [String] = []
            tagger.enumerateTags(in: myRange, unit: .word, scheme: .tokenType, options: []){tag, range  in
                let newToken = String(sent[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !newToken.isEmpty  {
                    currentToks.append(newToken)
                }
                return true
            }
            let doneSent = HashableSentence(id: String(snum), tokens: currentToks, conllMetas: [])
            sentsOut.append(doneSent)
        }
    if myConfig.parsingConfig.runExplicit{
        for sent in sentsOut{
            let printArray = Array(repeating: "#", count: 133).joined(separator: "")
            print(printArray)
            //            print("Sent :: \(sent.sentNum)")
            for (tnum, token) in sent.tokens.enumerated() {
                print("[\(tnum)]\t: \(token)")
            }
        }
    }
        return sentsOut
    }

//6 ultra simple tokenisation : spaces = only boundary
func applySimplexTokenisation(inputText: String) -> [String] {

    let tokensRaw = inputText.split(separator: " ")
    var tidyTokens: [String] = []
    for token in tokensRaw {
        if token != ""{
            tidyTokens.append(String(token))
        }
    }
    return tidyTokens
}



//6
func textFileToHashableSents(myConfig: TaggerConfig, pipeline: UDPipeline
//    inputURL: URL?,
//    sentencizingMethod: SentencizingMethod,
//    tokenizingMethod: TokenizingMethod,
//    lang: Language,
//    pipeline: UDPipeline,
//    runExplicit: Bool
) throws -> [HashableSentence]{
    var internalSentList: [HashableSentence] = []
    
    let sentencesAsStrings = try textFileToSentStrings(
        myConfig: myConfig,
        tokenizerPipeline: pipeline,
    )
//    print("Got sents as strings")
    internalSentList = try stringSentsToHashableSents(myConfig: myConfig,
        sents: sentencesAsStrings,
        pipeline: pipeline
    )
//    print("got internal sentlist")
    
    internalSentList = internalSentList.filter { sentence in
        // keep only sentences that have at 1+ tokens with non whitespace chars
        let hasValidContent = sentence.tokens.contains { token in
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
        }
        return hasValidContent
    }
    return internalSentList
}


// MARK: - Agnostic output making
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                 Agnostic output making functions
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//1. convert sent to dumpable string for selected format
func makeExportContent(myConfig: TaggerConfig) -> String{
    var returnString: String = ""
    switch myConfig.exportConfig.selectedExportFormat {
    case .conll, .conllTxt:
        returnString = myConfig.outputData.outSents.generateExportText()
    case .conllTidy:
        returnString = myConfig.outputData.outSents.generateExportTextTidy()
    case .xml, .xmlConll:
        returnString = sentListToXML(myConfig: myConfig)
    }
    return returnString
}


func makeExportContentFromMetas(run: RunOutput, additionalExportFormat: ExportFormat) -> String {
    var returnString: String = ""
    switch additionalExportFormat {
    case .conll, .conllTxt:
        returnString = run.runData.sents.generateExportText()
    case .conllTidy:
        returnString = run.runData.sents.generateExportTextTidy()
    case .xml, .xmlConll:
        returnString = sentListToXMLFromMetas(run: run, additionalExportFormat: additionalExportFormat)
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

//1.
func makeSafeXmlHeaderAttribs(
    xmlTitle: String,
    xmlAuthorName: String,
    selectedLanguage: Language,
    selectedTreebank: Language.Treebank,
    sourceFile: URL,
    maxPipelineStep: PipelineStep,
    runRetokeniser: Bool,
    tokenizingMethod: TokenizingMethod,
    sentencizingMethod: SentencizingMethod
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
    let xmlSafeMaxPipelineStep = maxPipelineStep.title.xmlEscaped
    let xmlSafeRunRetokeniser = String(runRetokeniser).xmlEscaped
    let xmlSafeTokenizingMethod = tokenizingMethod.rawValue.xmlEscaped
    let xmlSafeSentencizingMethod = sentencizingMethod.rawValue.xmlEscaped

    let outputStruct = XmlHeaderAttribs(
        xmlTitle: xmlSafeXMLTitle,
        xmlAuthorName: xmlSafeXMLAuthor,
        lang: xmlSafeLang,
        treebank: xmlsafeTreebank,
        taggingDate: xmlsafeDate,
        sourceFile: xmlsafeSourceFile,
        runID: runID,
        maxPipelineStep: xmlSafeMaxPipelineStep,
        runRetokeniser: xmlSafeRunRetokeniser,
        tokenizingMethod: xmlSafeTokenizingMethod,
        sentencizingMethod: xmlSafeSentencizingMethod,
    )
    return outputStruct
}

//3.
func sentListToXML(myConfig: TaggerConfig) -> String {
    
    let safeHeaderAttribs = myConfig.outputData.safeHeaderAttribs
    let sentences = myConfig.outputData.outSents
    let sentCount = String(sentences.count)
    let tokCount = String(sentences.generateTokCount())
    var outputStore: [String] = []

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
                <sourceDesc model="\(safeHeaderAttribs.lang.lowercased())" treebank="\(safeHeaderAttribs.treebank)" tagging_date="\(safeHeaderAttribs.taggingDate)" sourcefile="\(safeHeaderAttribs.sourceFile)" runID="\(safeHeaderAttribs.runID)" maxPipelineStep="\(safeHeaderAttribs.maxPipelineStep)" runRetokeniser="\(safeHeaderAttribs.runRetokeniser)" tokenizingMethod="\(safeHeaderAttribs.tokenizingMethod)" sentencizingMethod="\(safeHeaderAttribs.sentencizingMethod)" sentCount="\(sentCount)" tokenCount="\(tokCount)">
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

    outputStore.append(xmlHeader)
    for sentence in sentences {
        let addConllMetas: Bool = true
        if addConllMetas{
            outputStore.append(contentsOf: sentence.conllMetas)
        }
        outputStore.append(sentence.makeXMLsent(
            exportFormat: myConfig.exportConfig.selectedExportFormat,
            includeConllSentText: myConfig.exportConfig.includeConllSentText
            )
        )
    }
    outputStore.append(xmlFooter)
    
    return outputStore.joined(separator: "\n")
    
}
func sentListToXMLFromMetas(run: RunOutput, additionalExportFormat: ExportFormat) -> String {
    
    let safeHeaderAttribs = run.runMetas.safeHeaderAttribs
    let sentences = run.runData.sents
    let sentCount = String(sentences.count)
    let tokCount = String(sentences.generateTokCount())
    var outputStore: [String] = []

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
                <sourceDesc model="\(safeHeaderAttribs.lang.lowercased())" treebank="\(safeHeaderAttribs.treebank)" tagging_date="\(safeHeaderAttribs.taggingDate)" sourcefile="\(safeHeaderAttribs.sourceFile)" runID="\(safeHeaderAttribs.runID)" maxPipelineStep="\(safeHeaderAttribs.maxPipelineStep)" runRetokeniser="\(safeHeaderAttribs.runRetokeniser)" tokenizingMethod="\(safeHeaderAttribs.tokenizingMethod)" sentencizingMethod="\(safeHeaderAttribs.sentencizingMethod)" sentCount="\(sentCount)" tokenCount="\(tokCount)">
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

    outputStore.append(xmlHeader)
    for sentence in sentences {
        let addConllMetas: Bool = true
        if addConllMetas{
            outputStore.append(contentsOf: sentence.conllMetas)
        }
        outputStore.append(sentence.makeXMLsent(
            exportFormat: additionalExportFormat,
            includeConllSentText: run.runMetas.includeConllSentText
            )
        )
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
// 2. Run write coordinator :: run 3  with diff outputs then 4. No longer used
// 3. write string dump :: write string to named files on macOS AND iOS device ; No longer used
// 4. writtoFile ; No longer used


// write string to location
func saveFileToChosenLocation(myConfig: TaggerConfig, exportContent: String, runID: String) -> RunMetas{
    var savedURL: URL?
    var exportStatusMessage: String
    // deal with bad URL case
    guard let folderURL = myConfig.exportConfig.targetFolderURL else {
        if myConfig.parsingConfig.runExplicit{ print("Guard 661 fail") }
        exportStatusMessage = "Guard failure in save file to chosen location"
        return RunMetas(
            runID: runID,
            exportFormat: myConfig.exportConfig.selectedExportFormat,
            includeConllSentIdLine: myConfig.exportConfig.includeConllSentIdLine,
            includeConllSentText: myConfig.exportConfig.includeConllSentText,
            inputFileType: myConfig.inputConfig.inputFileType,
            lang: myConfig.parsingConfig.selectedLanguage.rawValue,
            maxPipelineStep: myConfig.parsingConfig.maxPipelineStep,
            message: exportStatusMessage,
            outputFileName: myConfig.exportConfig.fileName,
            processedCount: myConfig.progressConfig.processedCount,
            runResentenciser: myConfig.parsingConfig.runResentenciser,
            runRetokeniser: myConfig.parsingConfig.runRetokeniser,
            safeHeaderAttribs: myConfig.outputData.safeHeaderAttribs,
            savedURL: savedURL ??  nil,
            selectedRetokenisationType: myConfig.parsingConfig.selectedRetokenisationType,
            sentencizingMethod: myConfig.parsingConfig.sentencizingMethod,
            sourceFileName: myConfig.inputConfig.displayName,
            sourceFileURL: myConfig.inputConfig.selectedInputFile,
            targetFolderURL: myConfig.exportConfig.targetFolderURL,
            tokenizingMethod: myConfig.parsingConfig.tokenizingMethod,
            totalCount: myConfig.progressConfig.totalCount,
            treebank: myConfig.parsingConfig.selectedTreebank.short,
            unread:  true,

        )
    }
    if myConfig.parsingConfig.runExplicit{ print("Guard 661 pass")  }
    
    do {
        savedURL = try ExporterService.exportDataToFile(
            exportContent: exportContent,
            customName: "\(myConfig.exportConfig.fileName)_\(myConfig.parsingConfig.selectedTreebank.short)_\(myConfig.exportConfig.selectedExportFormat.rawValue)",
            targetFolderURL: folderURL,
            exportFormat: myConfig.exportConfig.selectedExportFormat,
            runExplicit: myConfig.parsingConfig.runExplicit,
        )
        exportStatusMessage = "Successfully exported to"
        if let savedURL {
            
            if myConfig.parsingConfig.runExplicit{
                print("Line 685: \(savedURL)")
            }
            exportStatusMessage += "\(savedURL.lastPathComponent)"
            if myConfig.parsingConfig.runExplicit {print (exportStatusMessage) }
        }
    } catch {
        
        exportStatusMessage = "Export failed: \(error.localizedDescription)"
        if myConfig.parsingConfig.runExplicit {
            print("return 690: \(exportStatusMessage)")
        }
    }
    // return for do-catch
    if myConfig.parsingConfig.runExplicit{
        print("return 694: ")
    }
    
    return RunMetas(
        runID: runID,
        exportFormat: myConfig.exportConfig.selectedExportFormat,
        includeConllSentIdLine: myConfig.exportConfig.includeConllSentIdLine,
        includeConllSentText: myConfig.exportConfig.includeConllSentText,
        inputFileType: myConfig.inputConfig.inputFileType,
        lang: myConfig.parsingConfig.selectedLanguage.rawValue,
        maxPipelineStep: myConfig.parsingConfig.maxPipelineStep,
        message: exportStatusMessage,
        outputFileName: myConfig.exportConfig.fileName,
        processedCount: myConfig.progressConfig.processedCount,
        runResentenciser: myConfig.parsingConfig.runResentenciser,
        runRetokeniser: myConfig.parsingConfig.runRetokeniser,
        safeHeaderAttribs: myConfig.outputData.safeHeaderAttribs,
        savedURL: savedURL,
        selectedRetokenisationType: myConfig.parsingConfig.selectedRetokenisationType,
        sentencizingMethod: myConfig.parsingConfig.sentencizingMethod,
        sourceFileName: myConfig.inputConfig.displayName,
        sourceFileURL: myConfig.inputConfig.selectedInputFile,
        targetFolderURL: myConfig.exportConfig.targetFolderURL,
        tokenizingMethod: myConfig.parsingConfig.tokenizingMethod,
        totalCount: myConfig.progressConfig.totalCount,
        treebank: myConfig.parsingConfig.selectedTreebank.short,
        unread:  true,
    )
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
func dumpDetailsForRunExplicit(myConfig: TaggerConfig, taggingInProgress:Binding<Bool>) throws  {
    guard myConfig.outputData.outSents.count > 0 else {
            taggingInProgress.wrappedValue = false
            throw ParseProcessingError.noRunOutput
    }

    if myConfig.parsingConfig.runExplicit {
        print("Printing conllRaw")
        print(myConfig.outputData.outSents.generateExportText())
        if let printPath = myConfig.exportConfig.targetFolderURL?.path(){
            print(printPath)
        } else {
            print("Problem with print path from URL 274")
        }
        print("output name = \(myConfig.exportConfig.fileName)")
        print("Main actor done, running function 277")
    }
    //no returns
}

//MARK: encapsulations
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                  encapsulation of run inputs, outputs
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------

//MARK: settings updaters
func makeTidyRunOutput(myConfig: TaggerConfig ) -> RunOutput {
    let runID = UUID().uuidString
    let exportContent = makeExportContent(myConfig: myConfig)
    let runData: RunData = RunData(
        runID: runID,
        sents: myConfig.outputData.outSents,
        exportContent: exportContent
    )
    
    let runMetas = saveFileToChosenLocation(
        myConfig: myConfig, exportContent: exportContent,
        runID: runID
    )
    
    let runOutput = RunOutput(
        runID: runID,
        runData: runData,
        runMetas: runMetas
    )
 
    return runOutput
}



//MARK: tokenisation functions
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                  Tokenisation functions
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------


//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                  sentencization
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//MARK: sentencisation
func makeHashableSentFromTestToks(tempTokens: [TempToken])-> HashableSentence?{
    guard tempTokens.count > 0 else {return nil}
    var keepTokens: [String] = []
    for item in tempTokens{
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



//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
//                                                  encapsulation of run inputs, outputs
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------
func makeSafeHeaderAttribs(myConfig: TaggerConfig, fileContainerModel: SourceFileContainerModel) -> XmlHeaderAttribs {
    let xmlSafeXMLAuthor = myConfig.exportConfig.xmlAuthorName.xmlEscaped != "" ? myConfig.exportConfig.xmlAuthorName.xmlEscaped : "author_unknown"
    let xmlSafeXMLTitle = myConfig.exportConfig.xmlTitle.xmlEscaped != "" ? myConfig.exportConfig.xmlTitle.xmlEscaped : "title"
    let xmlSafeLang = myConfig.parsingConfig.selectedLanguage.displayName.lowercased()
    let xmlsafeTreebank = myConfig.parsingConfig.selectedTreebank.short.xmlEscaped
    
    let formatter = DateFormatter()
    formatter.dateFormat = "y-MM-dd HH:mm"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let dateString = formatter.string(from:Date())
    let xmlsafeDate = dateString.xmlEscaped
    
    let xmlsafeSourceFile = fileContainerModel.localSandboxFileURL?.path().xmlEscaped ?? "unk"
    let runID = UUID().uuidString
    
    let maxPipelineStep = myConfig.parsingConfig.maxPipelineStep.title.xmlEscaped
    let runRetokeniser = String(myConfig.parsingConfig.runRetokeniser).xmlEscaped
    let tokenizingMethod = myConfig.parsingConfig.tokenizingMethod.rawValue.xmlEscaped
    let sentencizingMethod = myConfig.parsingConfig.sentencizingMethod.rawValue.xmlEscaped
    
    let outputStruct = XmlHeaderAttribs(
        xmlTitle: xmlSafeXMLTitle,
        xmlAuthorName: xmlSafeXMLAuthor,
        lang: xmlSafeLang,
        treebank: xmlsafeTreebank,
        taggingDate: xmlsafeDate,
        sourceFile: xmlsafeSourceFile,
        runID: runID,
        maxPipelineStep: maxPipelineStep,
        runRetokeniser: runRetokeniser,
        tokenizingMethod: tokenizingMethod,
        sentencizingMethod: sentencizingMethod,
    )
    return outputStruct
}

//                                                  end of main functions; experimental moved to function_dev
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
    let namedEntities: NLParseReturn
}
func getNLTags(text: String) -> NLParseResults{
    // get POS tags with inbuilt tagset, tagger -> No diff btw SCONJ, CCONJ, no proper noun
    var posTags: [NLReturn] = []
    var lemmas: [NLReturn] = []
    var namedEntities: [NLReturn] = []

    let tagger = NLTagger(tagSchemes: [ .lemma, .lexicalClass, .nameType])
    let options: NLTagger.Options = [ .omitWhitespace]
    tagger.string = text

    tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
        if let tag = tag {
            posTags.append(NLReturn(tokRange: String(text[tokenRange]), rawTag: tag.rawValue))
//            print("Token: \(String(text[tokenRange])) : tag: \(tag.rawValue)")
        }
        return true // signal to enumerator to keep going with enumeration
    }
    tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma, options: options) {tag, tokenRange in
        if let tag = tag {
            lemmas.append(NLReturn(tokRange: String(text[tokenRange]), rawTag: tag.rawValue))
//            print("Lemma: \(String(text[tokenRange])) : tag: \(tag.rawValue)")

        }
        return true
    }
    tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) {tag, tokenRange in
        if let tag = tag {
            namedEntities.append(NLReturn(tokRange: String(text[tokenRange]), rawTag: tag.rawValue))
//            print("Named: \(String(text[tokenRange])) : tag: \(tag.rawValue)")
        }
        return true
    }
    let posReturn: NLParseReturn = NLParseReturn(tag: "pos", nlReturn: posTags)
    let lemmaReturn: NLParseReturn = NLParseReturn(tag: "lemma", nlReturn: lemmas)
    let namedEntitiesReturn: NLParseReturn = NLParseReturn(tag: "namedEntities", nlReturn: namedEntities)
    return NLParseResults(posReturn: posReturn, lemmaReturn: lemmaReturn, namedEntities: namedEntitiesReturn)
}



func postprocessSentence(sentence: HashableSentence, parsedTokens: [Token], myConfig: TaggerConfig)->Sentence{
    
    if myConfig.parsingConfig.runExplicit {
        print("max requested step == \(myConfig.parsingConfig.maxPipelineStep.rawValue)")
    }
    let mySent: Sentence = Sentence(
        sentID: sentence.id,
        conllData: parsedTokens,
        conllMetas:  []
    )
    return mySent
}











//}
//        if let inputFileType = inputFileType{
//            self.inputFileType = inputFileType
//        } else {

//        func fooInit(inputFileType: InputFileType? = nil){
//                if let inputFileType = inputFileType{
//                    self.inputFileType = inputFileType
//                } else {
//                    if let foo = InputFileType(
//                        rawValue: TaggerConfig.resolveString(passed: nil, key: "inputFileTypeDefault", default: InputFileType.txt.rawValue)
//                    ){
//                        self.inputFileType = foo
//                    }
//                }
//        }
func removeFromBuiltSentArray(from array: inout [BuiltSentHolder], at offsets: IndexSet) {
    // 1. Guard against empty inputs
    guard !offsets.isEmpty else { return }
    
    // 2. Filter the offsets to ensure they are actually within the current bounds.
    let validOffsets = IndexSet(offsets.filter { $0 < array.count })
    // If no offsets are valid (e.g., the user swiped on a deleted cell), just bail.
    guard !validOffsets.isEmpty else { return }
    
    // 3. Perform the removal
    // We use the validOffsets to ensure we only touch existing indices.
    array.remove(atOffsets: validOffsets)
}

