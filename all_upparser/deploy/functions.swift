//
//  functions.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.

import CoreML
import Foundation
import NaturalLanguage
import SwiftUI
//----------------------------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------------------------

enum FileIngestionWorkflow {
    //MARK : helper functions: get data from file, and specialloader from inside bundle
    //  1. read from file :: std read file via URL, for use outside bundle. URL -> String
    //  2. load textFromBundledFile : read file via name from inside bundle. Filename -> String
    //  3. Detect lang in filename. regex to find lang in inputfilename for view
    //  4. test instantiate pipeline.
    //  5. dump scalars : can be used to dump logits
    // 2 starting points for data ingestion in pipeline: read from inside, outside bundle
    //1
    static func readFromFile(inputURL: URL?) throws -> String {
        guard let inputFile = inputURL else { throw PipelineError.GenericError.missingURL}
        do {
            let returnString = try String(contentsOf: inputFile, encoding: .utf8)
            return returnString
        } catch {
            return error.localizedDescription
        }
    }
    //2.
    static func loadTextFromBundledFile(inputFile: String, thisExtension: String) throws -> String{
        do {
            let normalizedText: String = try Bundle.main.loadText(inputFile, format: thisExtension)
            return normalizedText
        } catch {
            return PipelineError.LoadingError.fileLoadError.localizedDescription
        }
    }
    //3
    static func detectLangInFilename(inputURL: URL?)-> Language?{
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
}

enum ConLLParsingWorkflow{
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
    //  6. Make ConllLines runs 1-2-3, from URL, returning HashableSents to pass to Pipeline
    
    // note XML-Conll parsing needs access to these functions
    static func conllFileToHashableSentForPipeline(inputURL: URL?) throws -> [HashableSentence]{
        guard let inputFile = inputURL else {
            throw PipelineError.GenericError.missingURL
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

    // sub funcs called by the orchestrator
    //3.
    static func _conllLinesToSents(inputURL: URL, conllLines: [[String]]) throws -> [Sentence]{
        
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
                        throw PipelineError.IngestionError.conllParsingError(
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
                        col9: String(lineChunks[9]),
                        subTokens: []
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
    static func _makeConllLinesFromURL(inputURL: URL?) throws -> [[String]]{
        guard let inputURL else {
            throw PipelineError.GenericError.missingURL
        }
        do {
            let normalizedText = try FileIngestionWorkflow.readFromFile(inputURL: inputURL)
            guard  !normalizedText.isEmpty else {
                throw PipelineError.IngestionError.readFromSandboxError
            }
            
            let sentenceChunks: [String] = _conllBlobToChunks(conllBlob: normalizedText)
            guard !sentenceChunks.isEmpty else {
                throw PipelineError.IngestionError.conllLineIdentificationError
            }
            
            let hashableTokenLists: [[String]] = _conllChunksToLines(conllChunks: sentenceChunks)
            guard !hashableTokenLists.isEmpty else {
                throw PipelineError.IngestionError.conllChunkToLineError
            }
            return hashableTokenLists
            
        } catch {
            throw PipelineError.IngestionError.makeConllLinesFromURLError
        }
    }

    // funcs called by the subfuncs
    static func _conllBlobToChunks(conllBlob: String) -> [String] {
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
    static func _conllChunksToLines(conllChunks: [String]) -> [[String]]{
        var allSents: [[String]] = []
        for conllChunk in conllChunks{
            let currentSent = conllChunk.components(separatedBy: "\n")
            allSents.append(currentSent)
        }
        return allSents
    }
    
 }

enum xmlConllParsingWorkflow{
    // MARK: - XML-conll parsing
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    //                                              XML-conll parsing functions
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    
    // parse XMLconllu with XML parser, including making instance of class :: uses different parser with different output
    //1. parse xml-conll to get conll blob-pairs identical to CoNLL parsing
    static func _xmlConllToIdBlobPairs(from url: URL?) throws -> [XMLConllElement] {
        guard let url = url else {
            throw PipelineError.GenericError.missingURL
        }
        
        guard let parser = XMLParser(contentsOf: url) else {
            throw PipelineError.IngestionError.parserCreationError(file: url)
        }
        
        let delegate = SParser()
        parser.delegate = delegate
        
        let success = parser.parse()
        
        if !success{
            if let parserError = parser.parserError{
                throw parserError
            } else {
                throw PipelineError.IngestionError.xmlParserFailure(line: 0, reason:"Unknown XML parsing error")
            }
        }
        return delegate.results
    }
    //2. call 1. then apply CoNLL parsing functions
    static func xmlConllFileToHashableSentForPipeline(inputURL: URL?) throws -> [HashableSentence]{
        guard let inputURL else {
            throw PipelineError.GenericError.missingURL
        }
        
        var allSentences: [HashableSentence] = []
        let conllBlobs: [XMLConllElement] = try _xmlConllToIdBlobPairs(from: inputURL)
        let linesFromBlobs:[[String]] = ConLLParsingWorkflow._conllChunksToLines(conllChunks:conllBlobs.map { ($0.blob) })
        let intermedSents:[Sentence] = try ConLLParsingWorkflow._conllLinesToSents(inputURL: inputURL, conllLines: linesFromBlobs)
        allSentences.append(contentsOf: intermedSents.map {$0.hashableSentence} )
        
        return allSentences
    }
    
}

enum xmlParsingWorkflow{
    // MARK: - XML parsing
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    //                                                  XML parsing functions
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    // 1 function with SWParser, delegate, for std xml -> hashable sent. XMLConll needs 2 steps to conllise
    static func xmlToHashableSentForPipeline(inputURL: URL?) throws  -> [HashableSentence]{
        guard let inputURL else {
            throw PipelineError.GenericError.missingURL
        }
        
        guard let parser = XMLParser(contentsOf: inputURL) else {
            throw PipelineError.IngestionError.parserCreationError(file: inputURL)
        }
        
        let delegate = SWParser()
        parser.delegate = delegate
        let success = parser.parse()
        
        if !success{
            if let parserError = parser.parserError{
                throw parserError
            } else {
                throw PipelineError.IngestionError.xmlParserFailure(line: 0, reason:"Unknown XML parsing error")
            }
        }
        return delegate.results
        
    }
}

enum SentencizationWorkflow{
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    //                                                  sentencization
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    //MARK: sentencisation
    //func makeHashableSentFromTestToks(tempTokens: [TempToken])-> HashableSentence?{
    //    guard tempTokens.count > 0 else {return nil}
    //    var keepTokens: [String] = []
    //    for item in tempTokens{
    //        if item.form != ""{
    //            keepTokens.append(item.form)
    //        }
    //    }
    //    let returnObject = HashableSentence(id: UUID().uuidString, tokens: keepTokens, conllMetas: [])
    //    for x in returnObject.tokens{
    //        print(x)
    //    }
    //    return returnObject
    //    }
    //


    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    //                                                  TXT parsing functions
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    //  1. blob to sents: sentencise based on custom regex Rules                     :: String -> [String] w regex
    //  2. getSentencesWithNL: sentencise with inbuilt NLTokeniser                    :: String -> [String] w nlSentencizer
    //  2b/ applySentencizingMethodToStirng                                         :: String -> [String] method :  encapsulates 1, 2
    //  3. textFileToSentStrings : read in TXT file and use 1 or 2 to sentencise    :: File -> String -> [String] : escapsulates load, 2b
    
    //  4. sentStringToHashableSents: use pipeline or func5 to tokenise                :: [String] -> [Hashable] w choose
    //  5. getTokenisedSents: use inbuilt NL tagger to tokenise                        ::[String] -> [Hashable] w pipeline
    //  6. textFileToHashableSets : use func3 to sentencise then 4 to tokenise      :: File -> Hashable
    
    //1
    static func _blobToSents(blob: String,  myConfig: TaggerConfig) -> [String]{
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
    
    static func _getSentencesWithNL(text: String, myConfig: TaggerConfig)-> [String]{
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
    static func _applySentencizingMethodToString(normalizedText: String,  myConfig: TaggerConfig) throws -> [String] {
        
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
                let toksAsStrings = try TokenisationWorkflow.applyNaiveTokenisation(language: myConfig.parsingConfig.selectedLanguage, myString: normalizedText)
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
    static func textFileToSentStrings(myConfig: TaggerConfig) throws -> [String]{
        guard let _ = myConfig.inputConfig.selectedInputFile else {
            print("guard let failed loading form file")
            return []
        }
        if myConfig.parsingConfig.runExplicit{
            print("running text file to sent strings function")
        }
        let inputString = try FileIngestionWorkflow.readFromFile(inputURL: myConfig.inputConfig.selectedInputFile)
        guard !inputString.isEmpty else {
            throw PipelineError.LoadingError.fileLoadError
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
    
    static func desentenciseAndResentencise(sentsToDiscard: [HashableSentence], myConfig: TaggerConfig) throws -> [String]{
        
        let initialString = (sentsToDiscard.map {$0.detokenised}).joined(separator: " ")
        let normalizedText = initialString.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
        let resentencizerOutputStrings = try _applySentencizingMethodToString(normalizedText: normalizedText, myConfig: myConfig)
        return resentencizerOutputStrings
    }
    
    static func retokenisationEncapsulator(myConfig: TaggerConfig, pipeline: PipelineHelper, taggingInProgress: Binding<Bool>) throws -> [HashableSentence]{
        
        var sentencesAsStrings: [String] = []
        
        if myConfig.parsingConfig.runResentenciser {
            sentencesAsStrings = myConfig.inputData.resentencizerOutputStrings
        } else {
            for sent in myConfig.inputData.allSentences{
                sentencesAsStrings.append(sent.detokenised)
            }
        }
        
        let retokenisedSents = try TokenisationWorkflow.stringSentsToHashableSents(
            myConfig: myConfig,
            sents: sentencesAsStrings,
            pipeline: pipeline,
        )
        
        guard !retokenisedSents.isEmpty else {
            taggingInProgress.wrappedValue = false
            throw PipelineError.IngestionError.retokenisationError
        }
        
        return retokenisedSents
    }
    static func ingestSentEncapsulator(
        myConfig: TaggerConfig,
        pipeline: PipelineHelper
    ) throws -> [HashableSentence] {
        
        // need to filter sentences that are over len acceptable
        var allSentences: [HashableSentence] = []
        switch myConfig.inputConfig.inputFileType {
        case .conll:
            // resentencise internally in this function if set
            allSentences = try ConLLParsingWorkflow.conllFileToHashableSentForPipeline(
                inputURL: myConfig.inputConfig.selectedInputFile
            )
        case .manual:
            let myBuiltSents = myConfig.inputData.builtSents
            allSentences = myBuiltSents.compactMap {$0.toHashableSent(tempToks: $0.tempToks) }
            
        case .xml:
            // resentencise internally in this function if set
            allSentences = try xmlParsingWorkflow.xmlToHashableSentForPipeline(
                inputURL: myConfig.inputConfig.selectedInputFile
            )
        case .xmlConll:
            // resentencise internally in this function if set
            allSentences = try xmlConllParsingWorkflow.xmlConllFileToHashableSentForPipeline(
                inputURL: myConfig.inputConfig.selectedInputFile
            )
        case .txt:
            // this uses NaturalLanguage tagger as a sentenciser or custom ruleset (not yet written to sentencize blobs of text
            
            allSentences = try TokenisationWorkflow.textFileToHashableSents(myConfig: myConfig, pipeline: pipeline)
            
            if myConfig.parsingConfig.runExplicit{
                print("Mode a: \(allSentences.count) sents ")
            }
            
        }
        return allSentences //.filter {$0.tokens.count < maxSentLenForPipe }
        //TODO : report on the sents dropped, add progress for sentencisation as well as pipeline processing
        // TODO : add stop button
        // TODO: need to be able to process in batches, size = 500sent
        // TODO: add subtok filter after subtokenisation :: limit == 128
    }
    static func ingestSentences(currentStatus: String, myConfig: TaggerConfig, pipeline: PipelineHelper) throws -> [HashableSentence]{
        
        do {
            return try SentencizationWorkflow.ingestSentEncapsulator(myConfig: myConfig, pipeline: pipeline)
        } catch {
            throw PipelineError.IngestionError.noSentencesLoaded
        }
    }

}

enum TokenisationWorkflow{
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    //6 coordinator
    static func textFileToHashableSents(myConfig: TaggerConfig, pipeline: PipelineHelper
    ) throws -> [HashableSentence]{
        var internalSentList: [HashableSentence] = []
        
        let sentencesAsStrings = try SentencizationWorkflow.textFileToSentStrings(
            myConfig: myConfig
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

    //                                                  Tokenisation functions
    // 1, 2, . :: String -> [String]
    // 3,4 :: [String] -> [HashableSent]
    // 5. ::->> AttributedString

    //1.
    static func applyNaiveTokenisation(language: Language, myString: String) throws -> [String]{
        guard ![.DE, .ANG].contains(language) else {
            throw PipelineError.ConfigurationError.languageMethodConflict(language: language)
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
    
    //2 ultra simple tokenisation : spaces = only boundary
    static func applySimplexTokenisation(inputText: String) -> [String] {
        
        let tokensRaw = inputText.split(separator: " ")
        var tidyTokens: [String] = []
        for token in tokensRaw {
            if token != ""{
                tidyTokens.append(String(token))
            }
        }
        return tidyTokens
    }
    
    //3 -- this is a tokenisation function :: tokenise wiht NL
    static func _getTokenisedSentences(sents: [String], myConfig: TaggerConfig) -> [HashableSentence]{
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
    
    //4
    static func stringSentsToHashableSents(myConfig: TaggerConfig, sents: [String], pipeline: PipelineHelper) throws -> [HashableSentence]{
        
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
            switch myConfig.parsingConfig.modelArchitecture {
            case .distilbert:
                throw PipelineError.ConfigurationError.architectureConflict
            case .cnnBiLSTM:
                // retokenize everything with model
                // MARK: can change this IN to be testSentences
                
                if myConfig.parsingConfig.runExplicit{
                    print("sentencizing with trained")
                }
                for sentence in sents {
                    let tokenisedSent = try pipeline.tokenize(sentence)
                    internalSentList.append(tokenisedSent)
                }
            }
        }
        return internalSentList
    }
    
    // 5 : markup for UI
    static func markupTokenisationInSent(hashableSent: HashableSentence) -> AttributedString{
            
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
}

enum PostPipelineWorkflow{
    //----------------------------------------------------------------------------------------------------------------------------
    //                                                  encapsulation of run inputs, outputs
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    
    //MARK: settings updaters
    static func makeTidyRunOutput(myConfig: TaggerConfig ) -> RunOutput {
        let runID = myConfig.outputData.safeHeaderAttribs.runID
        let exportContent = GeneralOutputMakingWorkflow.makeExportContent(
            headers: myConfig.outputData.safeHeaderAttribs,
            sents: myConfig.outputData.outSents,
            exportFormat: myConfig.exportConfig.selectedExportFormat,
            includeConllSentText: myConfig.exportConfig.includeConllSentText
        )
        print("export content as made @ 1228 :: count == \(exportContent.count)")
        print("@lin819, maxLenWords == \(myConfig.parsingConfig.maxWords) and max SeqLen == \(myConfig.parsingConfig.maxSeqLen)")
        let runData: RunData = RunData(
            runID: runID,
            sents: myConfig.outputData.outSents,
            exportContent: exportContent
        )
        
        let runMetas = WritingWorkflow.saveFileToChosenLocation(
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
    
    static func postprocessSentence(sentence: HashableSentence, parsedTokens: [Token], myConfig: TaggerConfig)->Sentence{
        
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
    
    static func postprocessErrorSent(sentResult: OnSentResult) -> OutputError {
        let errorType = sentResult.resultType
        let sentence = sentResult.sentence
        var tokCount: Int
        var subTokCount: Int
        
        switch errorType {
        case .empty:
            tokCount = 0
            subTokCount = 0
        case .tooManyWords:
            tokCount = sentence.tokens.count
            subTokCount = -1
        case .tooManySubtoks, .success:
            tokCount = sentence.tokens.count
            subTokCount = sentResult.subtokCount
        case .otherError:
            tokCount = sentence.tokens.count > 0 ? sentence.tokens.count : -2
            subTokCount = sentResult.subtokCount > 0 ? sentResult.subtokCount : -2
        }
        
        return OutputError(
            sentence: sentence,
            tokCount: tokCount,
            subtokCount: subTokCount,
            errorType: errorType
        )
    }
}

enum GeneralOutputMakingWorkflow{
    // MARK: - Agnostic output making
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    //                                                 Agnostic output making functions
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------

    static func makeExportContent(headers: XmlHeaderAttribs, sents: [Sentence], exportFormat: ExportFormat, includeConllSentText: Bool)-> String{
            var returnString: String = ""
            switch exportFormat{
            case .conll, .conllTxt:
                returnString = sents.generateExportText()
            case .conllTidy:
                returnString = sents.generateExportTextTidy()
            case .xml, .xmlConll:
                returnString = XMLMakingWorkflow.sentListToXML(headers: headers, sents: sents, exportFormat: exportFormat, includeConllSentText: includeConllSentText)
            }
            return returnString
        }
    static func makeFilename() -> String {
        return String(UUID().uuidString.prefix(6))
    }

}

enum XMLMakingWorkflow{
    // MARK: - XML making
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    //                                                  XML-making functions :: called in agnostic function
    //----------------------------------------------------------------------------------------------------------------------------
    //----------------------------------------------------------------------------------------------------------------------------
    //1. make safe header attributes
    //2. Make XML string from list of sentences with output of 1, 2
    
    static func makeSafeHeaderAttribs(myConfig: TaggerConfig, fileContainerModel: SourceFileContainerModel) -> XmlHeaderAttribs {
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
        let xmlSafeMaxPipelineStep = myConfig.parsingConfig.maxPipelineStep.title.xmlEscaped
        let xmlSafeRunRetokeniser = String(myConfig.parsingConfig.runRetokeniser).xmlEscaped
        let xmlSafeTokenizingMethod = myConfig.parsingConfig.tokenizingMethod.rawValue.xmlEscaped
        let xmlSafeSentencizingMethod = myConfig.parsingConfig.sentencizingMethod.rawValue.xmlEscaped
        let xmlSafeArchitecture = myConfig.parsingConfig.modelArchitecture
        
        let outputStruct = XmlHeaderAttribs(
            xmlTitle: xmlSafeXMLTitle,
            xmlAuthorName: xmlSafeXMLAuthor,
            lang: xmlSafeLang,
            treebank: xmlsafeTreebank,
            taggingDate: xmlsafeDate,
            sourceFile: xmlsafeSourceFile,
            runID: runID,
            maxPipelineStep: xmlSafeMaxPipelineStep,
            modelArchitecture: xmlSafeArchitecture,
            runRetokeniser: xmlSafeRunRetokeniser,
            tokenizingMethod: xmlSafeTokenizingMethod,
            sentencizingMethod: xmlSafeSentencizingMethod,
            maxWords: String(myConfig.parsingConfig.maxWords),
            maxSeqLen: String(myConfig.parsingConfig.maxSeqLen)
        )
        return outputStruct
    }
//v2
    static func sentListToXML(headers: XmlHeaderAttribs, sents: [Sentence], exportFormat: ExportFormat, includeConllSentText: Bool) -> String {
        let safeHeaderAttribs = headers
        let sentences = sents
        let sentCount = String(sentences.count)
        print("sentCount inside sentlist to xml = \(sentCount)")
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
                <sourceDesc 
                    model="\(safeHeaderAttribs.lang.lowercased())"
                    treebank="\(safeHeaderAttribs.treebank)"
                    tagging_date="\(safeHeaderAttribs.taggingDate)"
                    sourcefile="\(safeHeaderAttribs.sourceFile)"
                    runID="\(safeHeaderAttribs.runID)"
                    maxPipelineStep="\(safeHeaderAttribs.maxPipelineStep)"
                    modelArchitecture="\(safeHeaderAttribs.modelArchitecture)",
                    runRetokeniser="\(safeHeaderAttribs.runRetokeniser)"
                    tokenizingMethod="\(safeHeaderAttribs.tokenizingMethod)"
                    sentencizingMethod="\(safeHeaderAttribs.sentencizingMethod)"
                    maxWords="\(safeHeaderAttribs.maxWords)"
                    maxSeqLen="\(safeHeaderAttribs.maxSeqLen)">
                    sentCount="\(sentCount)"
                    tokenCount="\(tokCount)">
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
                exportFormat: exportFormat,
                includeConllSentText: includeConllSentText
            )
            )
        }
        outputStore.append(xmlFooter)
        let returnItem = outputStore.joined(separator: "\n")
        print("returnItem 937 count = \(returnItem.count)")
        return returnItem
        
    }
}

enum WritingWorkflow{
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
    static func saveFileToChosenLocation(myConfig: TaggerConfig, exportContent: String, runID: String, additional: AdditionalExportParams? = nil) -> RunMetas{
        var savedURL: URL?
        var exportStatusMessage: String

        print("@line1046, maxLenWords == \(myConfig.parsingConfig.maxWords) and max SeqLen == \(myConfig.parsingConfig.maxSeqLen)")

        var updatedExportFormat: ExportFormat = myConfig.exportConfig.selectedExportFormat
        var updatedIncludeConllSentText: Bool = myConfig.exportConfig.includeConllSentText
        // if running an additional export, use these values passed through the optional
        if let additionalParams = additional{
            updatedExportFormat = additionalParams.exportFormat
            updatedIncludeConllSentText = additionalParams.includeConllSentText
        }
        
        guard let folderURL = myConfig.exportConfig.targetFolderURL else {
            if myConfig.parsingConfig.runExplicit{ print("Guard 661 fail") }
            exportStatusMessage = "Guard failure in save file to chosen location"
            return RunMetas(
                runID: runID,
                exportFormat: updatedExportFormat,
                includeConllSentIdLine: myConfig.exportConfig.includeConllSentIdLine,
                includeConllSentText: updatedIncludeConllSentText,
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
                unread: true
            )
        }
        if myConfig.parsingConfig.runExplicit{ print("Guard 661 pass")  }
        
        do {
            print("export content inside Exporter service count == \(exportContent.count)")
            savedURL = try PipelineServices.ExporterService.exportDataToFile(
                exportContent: exportContent,
                customName: "\(myConfig.exportConfig.fileName)_\(myConfig.parsingConfig.selectedTreebank.short)_\(updatedExportFormat.rawValue)",
                targetFolderURL: folderURL,
                exportFormat: updatedExportFormat,
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
    
    static func runWriteCoordinator(lines: [String], rawLines: [String]) throws {
        try writeStringDump(lines)
        try writeStringDump(rawLines)
        
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputPath = docsDir.appendingPathComponent("output.conllu").path
        try writeToFile(rawLines.joined(separator: "\n"), outputPath)
    }
    
    static func writeStringDump(_ lines: [String]) throws -> URL {
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
    
    static func writeToFile(_ content: String, _ path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
        print("Wrote file to: \(url)")
        
    }
}

enum PrintWorkflow{
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
    static func printJSONError(_ error: Error) {
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
    static func printFromConllSents(outsents: [Sentence]) throws -> URL{
        
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
    static func dumpDetailsForRunExplicit(myConfig: TaggerConfig, taggingInProgress:Binding<Bool>) throws  {
        guard myConfig.outputData.outSents.count > 0 else {
            taggingInProgress.wrappedValue = false
            throw PipelineError.ProcessingError.noRunOutput
        }
        
        if myConfig.parsingConfig.runExplicit {
            print("Printing conllRaw")
            print(myConfig.outputData.outSents.generateXMLsentences())
            //        print(myConfig.outputData.outSents.generateExportText())
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
    
    static func dumpScalars(_ text: String, maxChars: Int = 50) {
        // called in runTest() function
        for scalar in text.unicodeScalars.prefix(maxChars) {
            print("\(scalar) -> \(scalar.value)")
        }
    }

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


//func testInstantiatePipeline(myConfig: TaggerConfig)   -> String {
//    // test instantiation of pipeline class based on params chosen
//    var outputString: String = ""
//
//    Task{
//        do {
//            let _ = try CNNBiLSTMPipeline(myConfig: myConfig)
//            await MainActor.run {
//                outputString = "Success"
//            }
//        } catch {
//            await MainActor.run {
//                outputString = "Fail : \(error.localizedDescription)"
//            }
//        }
//    }
//    return outputString
//}
//5

////3.


