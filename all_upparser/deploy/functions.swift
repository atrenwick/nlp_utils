//
//  ClassMethods.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
// methods for use across classes

import Foundation
import CoreML


// MARK: - MLMultiArray helpers

func makeIntArray(_ values: [Int32], shape: [NSNumber]) throws -> MLMultiArray {
    let arr = try MLMultiArray(shape: shape, dataType: .int32)
    for (i, v) in values.enumerated() {
        arr[i] = NSNumber(value: v)
    }
    return arr
}

func makeCharIdArray(_ charIdLists: [[Int32]], maxWordLen: Int) throws -> MLMultiArray {
    let t = charIdLists.count
    let arr = try MLMultiArray(
        shape: [1, NSNumber(value: t), NSNumber(value: maxWordLen)], dataType: .int32
    )
    for i in 0..<arr.count { arr[i] = 0 } // pad_id is always 0 by Vocab convention
    for (wi, ids) in charIdLists.enumerated() {
        for (ci, cid) in ids.enumerated() {
            arr[[0, wi, ci] as [NSNumber]] = NSNumber(value: cid)
        }
    }
    return arr
}

func argmax(_ arr: MLMultiArray, prefix: [Int], dimSize: Int) -> Int {
    var best = 0
    var bestVal = -Double.infinity
    for c in 0..<dimSize {
        let idx = (prefix + [c]).map { NSNumber(value: $0) }
        let v = arr[idx].doubleValue
        if v > bestVal {
            bestVal = v
            best = c
        }
    }
    return best
}

func dumpScalars(_ text: String, maxChars: Int = 50) {
    // called in runTest() function
    for scalar in text.unicodeScalars.prefix(maxChars) {
        print("\(scalar) -> \(scalar.value)")
    }
}

//MARK: exporting to file
//// other functions
func writeStringDump(_ lines: [String]) throws -> URL {
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

func runWriteCoordinator(lines: [String], rawLines: [String]) throws {
    try writeStringDump(lines)
    try writeStringDump(rawLines)

    let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let outputPath = docsDir.appendingPathComponent("output.conllu").path
    try writeToFile(rawLines.joined(separator: "\n"), outputPath)

    
    //no returns
}

func untokenisedInputToSents(text: [String], languageCode: LanguageCode) throws -> [[String]]{
    var returnItem: [[String]] = []
//        var currentSent: [String] = []
    let pipeline = try UDPipeline(languageCode: languageCode.rawValue, treebank: "gsd")
    for (_, sent) in text.enumerated(){
        let currentSent = try  pipeline.tokenize(sent)
        for chunk in currentSent{
            returnItem.append(chunk.tokens)
        }
    }
    return returnItem
}

//
//func untokenisedInputToSents(text: [String]) throws -> [[String]]{
//    var returnItem: [[String]] = []
////        var currentSent: [String] = []
//
//    for (_, sent) in text.enumerated(){
//        let currentSent = try tokenize(sent)
//        for chunk in currentSent{
//            returnItem.append(chunk)
//        }
//    }
//    return returnItem
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
//        let newSent = TokenisedSentence(id: String(count), tokens: tidyToks)
//        returnItem.append(newSent)
//    }
//    return returnItem
//}
//





func applyNaiveTokenisationToString(inputText: String) -> [String]{
    return inputText.components(separatedBy: " ")
}
func getTokens(languageCode: String, method: TokenisationMethod, inputFile: String = "", targetString: String = "") -> [[String]]{
    var internalList: [[String]] = []
    switch method {
    case .conll:
        print("Use conll input as tokenisation")
        return makeConllLinesFromFile(inputFile: inputFile)

    case .retokenise:
        print("Use tokeniser to predict")
        do {
            let pipeline = try UDPipeline(languageCode: languageCode, treebank: "gsd")
            let tokenisedSentences = try pipeline.tokenize(targetString)
            print("printing chunks")
            print(tokenisedSentences)
            print("End chunks")

            for sent in tokenisedSentences{
                internalList.append(sent.tokens)
            }
        }
        catch {
            let errorDesc = error.localizedDescription
            print("error in get tokens function with pipeline")
            print(errorDesc)
        }
        return internalList
    }
}


    
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
        // Reads raw text directly from your sandbox URL
        let normalizedText = try String(contentsOf: inputFile, encoding: .utf8)
        print("normalizedText passed")
        // split the string into sentence chunks
        let sentenceChunks: [String] = getConllSentenceChunks(rawConllString: normalizedText)
        print("chunked")
        // split each chunk == sentence into its lines
        let pretokenisedSentences: [[String]] = makeConllLinesFromChunks(conllSentences: sentenceChunks)
        print("Got file from conll")
        return pretokenisedSentences
        // Pass normalizedText downstream to your parsing functions...
    } catch {
        print("Failed to read text from sandbox file: \(error)")
    }
    return []
}



func makeConllLinesFromFile(inputFile: String) -> [[String]]{
    
    // load source file as a string from bundle
    let normalizedText: String = Bundle.main.loadText(inputFile, format: "conllu")
    // split the string into sentence chunks
    let sentenceChunks: [String] = getConllSentenceChunks(rawConllString: normalizedText)
    
    // split each chunk == sentence into its lines
    let pretokenisedSentences: [[String]] = makeConllLinesFromChunks(conllSentences: sentenceChunks)
    return pretokenisedSentences
}
//this removes emptysents made bt makeConllLinesFromFile
func makeTokenisedSentsFromFile(inputSents: [[String]]) -> [TokenisedSentence]{
    // ge tinput from getPretokenised
    var outputTokSents: [TokenisedSentence] = []
    var currentSentId: String = ""
    for inputSent in inputSents {
        var currentToks: [String] = []
        for inputLine in inputSent {
            if inputLine.hasPrefix("#") {
                currentSentId = inputLine
            } else {
                let fields = inputLine.split(separator: "\t")
                guard fields.count > 1 else {
                    // Blank line (or malformed row) -- treat it as the end of
                    // the current sentence, package up what we've collected so
                    // far, and start fresh for the next one.
                    if !currentToks.isEmpty {
                        outputTokSents.append(TokenisedSentence(id: currentSentId, tokens: currentToks))
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
            outputTokSents.append(TokenisedSentence(id: currentSentId, tokens: currentToks))
        }
    }
    return outputTokSents
}


// MARK:  functions to parse existing .conll documents
/// step1 is in Bundle.main
/// step2 :: get sentences
func getConllSentenceChunks(rawConllString: String) -> [String] {
    // iterate over chars to find boundaries between sents in rawConll : find \n# seq
    // return  : 1 string = 1 sentence, in a list
    let char1 = "\n"
    let char2 = "#"
    let chars = Array(rawConllString)
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
func makeConllLinesFromChunks(conllSentences: [String]) -> [[String]]{
    var allSents: [[String]] = []
    for conllSentence in conllSentences{
        let currentSent = conllSentence.components(separatedBy: "\n")
        allSents.append(currentSent)
//        allSents.append(contentsOf: conllSentence.components(separatedBy: "\n"))
        
    }
    return allSents
}

//// step4 :
// make sentence object
func makeConllSentv1(conllLines: [[String]]) -> [ConllSent] {
///this is the old version of the func that returns an empty sent at start
    let printScalars = false
    var allSents: [ConllSent] = []
    for currentSent in conllLines {
        var sentMetaLine: String = ""
        var tokenList: [UDToken] = []
        for line in currentSent {
            if line.hasPrefix("#"){
                sentMetaLine = line
            //} else if line != "" {
                // for numbered lines::
                
                if let fooLine = line.split(separator: "\n", omittingEmptySubsequences: false).first {
                    if printScalars{
                        for scalar in fooLine.unicodeScalars {
                            print("\(scalar) -> \(scalar.value)")
                        }
                    }
                }
                
                let lineChunks: [String] = line.components(separatedBy: "\t")
                
                let newTok = UDToken(
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
                //print("\(newTok.tokid) is the tokID of \(newTok.form)")
                tokenList.append(newTok)
            }
        }
        let newSentenceObject = ConllSent(
            sentID: sentMetaLine,
            conllData: tokenList)
        allSents.append(newSentenceObject)
    }
    return allSents
}

func makeConllSent(conllLines: [[String]]) -> [ConllSent]{
    
    var outputSentences: [ConllSent] = []
    var currentSentId: String = ""
    let inputSents = conllLines // rename for similarity to model
    for inputSent in inputSents {
        var currentToks: [UDToken] = []
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
                        let newSentenceObject = ConllSent(
                            sentID: currentSentId,
                            conllData: currentToks)
                        outputSentences.append(newSentenceObject)
                        currentToks = []
                        currentSentId = ""
                    }
                    continue
                }
                
                let newTok = UDToken(
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
            let newSentenceObject = ConllSent(
                sentID: currentSentId,
                conllData: currentToks)
            outputSentences.append(newSentenceObject)
            currentToks = []
            currentSentId = ""
        }
    }
    return outputSentences
}



//MARK: functions not called
func runConllFileParserPipe(pretokenisedSentences: [[String]]) -> [ConllSent]{
    
    let conllSents: [ConllSent] = makeConllSent(conllLines: pretokenisedSentences)
    
    return conllSents
}

func getSentsForPipelineFromPretokConll(inputFile: String) ->[TokenisedSentence]{
    let pretokenisedSentences = makeConllLinesFromFile(inputFile: inputFile)
    let outputSentences  = makeTokenisedSentsFromFile(inputSents: pretokenisedSentences)
	return outputSentences
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

    

    
            

