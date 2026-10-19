//
//  function_dev.swift
//  Tagger
//
//  Created by Adam on 13/10/2026.
//

import Foundation
// in progress
//func stringSentToHashableWithoutRetokenizing(sents: [String], lang: Language, pipeline: UDPipeline, sentencizingMethod: SentencizingMethod) -> [HashableSentence] {
//    var returnSents: [HashableSentence]
//
//    // this can only run in custom mode, as NLSentenciser and trained both require `String` input
//    // custom uses logic rules based on EOS markers to keep tokenisation and mark, split EOS ;
//    switch sentencizingMethod{
//    case .nlSentencizer:
//        // do this for nl sentencizer
//        let normalizedText = sents.joined(separator: " ")
//        let sentencesAsStrings = getSentencesWithNL(text: normalizedText, lang: lang)
//        returnSents = sentsAsStringsToHashableSents(arg1: String)
//    case .naive:
//        // do this
//    case .trained:
//        // do this
//    case .custom:
//        // do this
//    }
//    return returnSents
//}
//

//1.  apply naive tokenisation - spaces = token boundaries
//2. make hashable sent from manually redefinable tokens
//3. Make string of Sent for View, with red / as token boundary





//MARK: tokenisation

///Tokenisation -> core tokeniser from moonshot:
// COPY
//struct RegexLangPatternToLangMap: Identifiable{
//    var id = UUID()
//    let string: String
//    let langValue: Language
//    var asRegex: Regex<Substring>{
//        try! Regex(string)
//    }
//}
//let myMaps: [RegexLangPatternToLangMap] = [
//    RegexLangPatternToLangMap(string: #"[_\.]fr|^fr_"#, langValue: .FR),

//END_COPY
//TODO : regexMap like RegexLangPatternToLangMap
func run_tokeniser_core(thisText: String, lang: String, hyphen_join_value:Bool) -> String{
    var thisText: String = thisText
    thisText = thisText.replacingOccurrences(of: #"[\x{0D}\x{A0}\r\n\t\\]"#, with: " ", options: .regularExpression)
//    thisText = thisText.replacingOccurrences(of: #"(  )+"#, with: " ", options: .regularExpression)
//    thisText = thisText.replacingOccurrences(of:"  ", with: " ", options: .regularExpression)
    
//    thisText = thisText.replacingOccurrences(of: #"\.\.\."#, with:" … ", options: .regularExpression)

    thisText = thisText.replacingOccurrences(of: #"et al"#, with:#"et_al"#, options: .regularExpression)
    thisText = thisText.replacingOccurrences(of: #"et\. al"#, with:#"et_al"#, options: .regularExpression)
    thisText = thisText.replacingOccurrences(of: #"et\. al\."#, with:#"et_al"#, options: .regularExpression)
    // UPDATE : thisText = thisText.replacingOccurrences(of: #"\bet\.? al\.?"#, with: "et_al",options: .regularExpression)

    thisText = thisText.replacingOccurrences(of: #"e\.g\."#, with:#"e_g_"#, options: .regularExpression)
    // UPDATE : thisText = thisText = thisText.replacingOccurrences(of: #"\be\.?\s?g\b\.?"#,     with: "e_g", options: [.regularExpression, .caseInsensitive])

    thisText = thisText.replacingOccurrences(of: #"i\.e\."#, with:#"i_e_"#, options: .regularExpression)
    
    
    thisText = thisText.replacingOccurrences(of: #"i\. e \. ,"#, with:#"i_e_"#, options: .regularExpression)
    thisText = thisText.replacingOccurrences(of: #"i\. e \."#, with:#"i_e_"#, options: .regularExpression)
//    thisText = thisText.replacingOccurrences(of: #",\.$"#, with:#"."#, options: .regularExpression)
//    thisText = thisText.replacingOccurrences(of: #",\. "#, with:#". "#, options: .regularExpression)
//    thisText = thisText.replacingOccurrences(of: #"\.,"#, with:#". "#, options: .regularExpression)

//    thisText = thisText.replacingOccurrences(of: #"(htt(p|ps)://.+?($| ))"# ,with:" _URL_ ", options: .regularExpression)
    
//    if ["fr", "FR"].contains(lang) {
//        thisText = thisText.replacingOccurrences(of: #"[’''’]"#, with:"' ", options: .regularExpression)
////        thisText = runFRonlyReplacements(thisText: thisText)
//    }
//    if ["en", "EN"].contains(lang) {
//        thisText = thisText.replacingOccurrences(of: #"[’''’]"#, with:"' ", options: .regularExpression)
//        thisText = thisText.replacingOccurrences(of: #"[“”]"#, with:#"""#, options: .regularExpression)
//    }
    
//    thisText = thisText.replacingOccurrences(of: #"([,\]\[;:\-&\(\)?!\.«»“”"])"#, with:#" $1 "#, options: .regularExpression)
    
//    if hyphen_join_value {
//        thisText = thisText.replacingOccurrences(of: #" (-) "#, with:#"$1"#, options: .regularExpression)
//    }   else {
//        thisText = thisText.replacingOccurrences(of: #"(–)"#, with:#" $1 "#, options: .regularExpression)
//    }
    
    thisText = thisText.replacingOccurrences(of: #"\. "#, with:#" . "#, options: .regularExpression)
    thisText = thisText.replacingOccurrences(of:"  ",with:" ", options: .regularExpression)
    thisText = thisText.replacingOccurrences(of:#"\n"#, with:#" \n "#, options: .regularExpression)
    thisText = thisText.replacingOccurrences(of:#"(  )+"#, with:" ", options: .regularExpression)
    thisText = thisText.replacingOccurrences(of:#"  "#, with:" ", options: .regularExpression)
    thisText = thisText.replacingOccurrences(of:#"\t\t"#, with:#"\t"#, options: .regularExpression)
    thisText = thisText.replacingOccurrences(of:#"(\n\n)+"#, with:#"\n"#, options: .regularExpression)
    thisText = thisText.replacingOccurrences(of:#"^ | $"#, with:"", options: .regularExpression)
    return thisText
    
}
func tokeniseEN(inputString: String, selectedLanguage: Language) -> [Substring]{
    
    var currentString = inputString.replacing(RegexStash.tokeniseEN.enPunctuation,  with: " $0 ")
    currentString = currentString.replacing(RegexStash.tokeniseEN.apostopheCatcher, with: "$0 ")
    currentString = currentString.trimmingCharacters(in: .whitespacesAndNewlines)
    return currentString.split(whereSeparator: {$0 == " "})
}


let apostropheReplacementsFR: [String: String] = [
    "jourd'hui": "jourdhui",
    "rud'homm": "rudhomm",
]
let apostropheUnreplacementsFR = Dictionary(uniqueKeysWithValues: apostropheReplacementsFR.map { ($1, $0) })

let apostropheRegexUnreplaceFR = try! Regex(
    apostropheUnreplacementsFR.keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
)
let apostropheRegexReplaceFR = try! Regex(
    apostropheReplacementsFR.keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
)

func tokeniseFR(inputString: String, selectedLang: Language) -> [Substring] {
    
    let apostrophes: Set<Character> = ["\u{2018}", "\u{2019}", "\u{02BC}", "\u{00B4}", "`"]
    let rulesFR: [(regex: Regex<AnyRegexOutput>, keepMatch: Bool)] = [
        (RegexStash.tokeniseFR.punctRegexFR, true),
        (RegexStash.tokeniseFR.contractionRegexFR, true),
        (RegexStash.tokeniseFR.pronounRegexFR, true),
        (RegexStash.tokeniseFR.eosBreakCatchRegexFR, false),
    ]

    var frResult = inputString.replacing(apostropheRegexReplaceFR) { match in
        let matchedText = String(match.0)
        if let replacement = apostropheReplacementsFR[matchedText] {
            return replacement      // return match
        }
        return matchedText          // need somethign to return if regex settings set to, eg case insensitive, and dict not perfectly aligned to these
    }

    frResult = String(frResult.map { apostrophes.contains($0) ? "'" : $0 })

    for rule in rulesFR {
        frResult = frResult.replacing(rule.regex) { match in
            rule.keepMatch ? " " + match.0.description : " "
        }
    }

    var preSplit = frResult.trimmingCharacters(in: .whitespacesAndNewlines)
    
    preSplit = preSplit.replacing(apostropheRegexUnreplaceFR) { match in
        apostropheUnreplacementsFR[String(match.0)] ?? String(match.0)
    }
    // NOTE : here, \n\n still present as LB/EOP
    return preSplit.split(whereSeparator: {$0 == " "})
}

// testing tokenisations
let foobar = "Il y a deux prud' hommes qui sont là aujourd' hui. Que doit-on leur dire ?"
//let modified = runFRonlyReplacements(thisText: foobar)
//print(modified)

let veryModified = run_tokeniser_core(thisText: foobar, lang: "fr", hyphen_join_value: false)
let rawLength = inputText.count
let rawSplitLength = inputText.split(separator: " ").count
let modInput = run_tokeniser_core(thisText: inputText, lang: "fr", hyphen_join_value: false)
//let thisModifiedText = getTokensFromText(inputText: modInput)
//let thisCount = thisModifiedText.count

//print("Input chars: \(rawLength)")
//print("Input words: \(rawSplitLength)")
//print("Mod length: \(modInput.count)")
//print("Mod words: \(thisCount)")


let testFileRaw = "/Users/Adam/Library/CloudStorage/Dropbox/swiftprojects/project7moonshot/old_data/textSample.txt"

let myURL = URL(fileURLWithPath: testFileRaw)
var inputText: String = ""



//# use lang argument to load language specific abbreviations
func markEosEnds(selectedLanguage: Language, tokListIn: [Substring])-> [EosTok]{
    guard [.FR, .EN].contains(selectedLanguage) else {
        return []
    }
    // common lists
    let punctList = [";","-",","]
    let eosList = ["!", "?", ".", "\n"]
    let rightEls = ["”","’", "»","\"", "}", ")"]
    let excList = ["1","2","3","4","5","6","7","8","9","0", "com", "net", "L","M", "R"]
    
    // get abbrev list
    var abrevList: [String]
    switch selectedLanguage {
    case .EN:
        abrevList = ["Mr", "Mrs","Dr","Bt"]
    case .FR:
        abrevList = ["M", "Mme","Dr"]
    default:
        return []
    }

    let compoundList1: [String] = punctList + abrevList
    let compoundList2: [String] = punctList + excList
    
    var outputList: [EosTok] = []
    var prevTok: String = "__"
    var nextTok: String = "__"
    //# iterate over all but the last w block, which will be marked EOS
    
    let tokList = tokListIn.map {String($0)}
    for (wnum, tok) in tokList.enumerated(){
        if wnum+1 < tokList.count {  // get next block if exists
            nextTok = tokList[wnum+1]
            if eosList.contains(tok){
                    outputList.append(EosTok(form: tok, isEOS: "true", reason: "Rights"))
            } else {
            outputList.append(EosTok(form: tok, isEOS: "false", reason: "notExc"))
            }
            
        } else {
            outputList.append(EosTok(form: tok, isEOS: "true", reason: "end of list"))
        }
    }
    return outputList
    //[Token(tokid: 1, form: "placeholder", lemma: "_", upos: "_", xpos: "_", feats: "_", head: "_", deprel: "_", col8: "_", col9: "_")]
}


// uses next token approach :: worth hassle? use this or current-approach and final loop to take latter of consecutive True values
func markSentEndsNextTokApproach(tokens: [String], lang: String, approach: EosApproach) -> [Item] {
    guard !tokens.isEmpty else {
        return []
    }
    
    // 1. Setup Constants
    let eosList = ["!", "?", ".", "\n"]
    let punctList = [";", "-", ","]
    let rightEls = ["”", "’", "»", "\"", "}"]
    let exclList = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "com", "net", "L", "M", "R"]
    
    var abbrevList: [String] = []
    if lang == "en" {
        abbrevList = ["Mr", "Mrs", "Dr", "Bt"]
    } else if lang == "fr" {
        abbrevList = ["M", "Mme", "Dr"]
    }
    
    let compoundList1 = Set(exclList + abbrevList)
    let compoundList2 = Set(punctList + exclList)
    var results = [Item]()
    
    // 2. Initialize Flags
    // We create a boolean array to track which indices are ends of sentences
    // and a string array to track the reasons.
    var isEosFlags = [Bool](repeating: false, count: tokens.count)
    var reasonFlags = [String?](repeating: nil, count: tokens.count)
    
    // 3. The "Next Token" Logic Loop
    // We iterate up to the second-to-last token because the last token
    // can't have a "next" token to influence.
    if tokens.count > 1 {
        for i in 0..<(tokens.count - 1) {
            let currentTok = tokens[i]
            let prevTok = i > 0 ? tokens[i-1] : "__"
            let nextTok = tokens[i+1]
            
            var newItem = Item(text: currentTok)
            // If current token is an EOS character and previous was not an abbreviation
            if eosList.contains(currentTok) && !abbrevList.contains(prevTok) {
                
                // CASE A: The next token is a "Right" boundary (e.g., "!")
                if rightEls.contains(nextTok) {
                    switch approach{
                    case .current:
                        newItem.isEOS = true
                        newItem.varReason = "rights"
                        
                    case .next:
                        isEosFlags[i + 1] = true
                        reasonFlags[i + 1] = "rights"
                    }
                }
                // CASE B: The next token is a new sentence (not in compound list and capitalized)
                else if !compoundList2.contains(nextTok) && !nextTok.isLower {
                    switch approach{
                    case .current:
                        newItem.isEOS = true
                        newItem.varReason = "notExc"
                        
                    case .next:
                        isEosFlags[i] = true
                        reasonFlags[i] = "notExc"
                    }
                }
            }
            results.append(newItem)
        }
        
        // 4. Handle the final token separately (no "next" token exists)
        if let lastTok = tokens.last {
            switch approach {
            case .current:
                results.append(
                    Item(text: lastTok, isEOS: true, varReason: "FINAL"))
            case .next:
                isEosFlags[tokens.count - 1] = true
                reasonFlags[tokens.count - 1] = "eos_list"
            }
        }
    } else if let firstTok = tokens.first {
        // Handle single-token list
        switch approach {
        case .current:
            results.append(
                Item(text: firstTok, isEOS: false, varReason: "_FIRST_")
            )
            
        case .next:
            isEosFlags[0] = false
            reasonFlags[0] = "_FIRST_"
        }
    }
    switch approach{
    case .current:
        for i in 0..<(results.count - 1) {
            if results[i].isEOS && results[i+1].isEOS {
                // If the current one is just a punctuation and the next one is the "Right" boundary
                // or the next one is the "true" EOS, we can potentially flip the current one.
                results[i].isEOS = false
            }
        }
    case .next:
        // 5. Construct the final result
        for i in 0..<tokens.count {
            var item = Item(text: tokens[i])
            item.isEOS = isEosFlags[i]
            item.varReason = reasonFlags[i]
            results.append(item)
        }
        
    }
    return results
}

// dev helpers
struct Item {
    var text: String
    var isEOS: Bool = false
    var varReason: String? = nil
}

struct EosTok: Identifiable, Hashable{
    var id = UUID()
    let form: String
    let isEOS: String
    let reason: String
    
}

