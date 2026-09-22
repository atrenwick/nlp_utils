//
//  UDTestView.swift
//
//  A minimal SwiftUI screen for testing the UDPipeline (see UDPipeline.swift)
//  against a hardcoded sentence. Tap "Test" to run both Core ML models and
//  print the resulting CoNLL-U-style lines.
//
//  This is named UDTestView (not ContentView) so it doesn't collide with
//  the ContentView.swift Xcode's app template already created for you --
//  see the README for how to wire this in.
//
import SwiftUI


struct UDPipelineTestView: View {

    // present an dused in PipelineSettings View:
        @State private var selectedTreebank: Language.Treebank = .enTB1
    
        @State private var progressBarStyle: ProgressBarStyle = .tqdm
        @State private var errorMessage: String?
        @State private var processedCount = 0
        @State private var totalCount = 0
        @State private var startTime: Date?
        @State private var appleProgress = Progress(totalUnitCount: 1)
        @State private var hasStarted = false
    @State private var selectedLanguage: Language = .FR
    @State private var currentTokenisationType: TokenisationMethod = .conll
    @State private var isRunningConll = false
    @State private var isRunningRaw = false
    //MARK: vars for intermediate states and outputs
    @State private var outputLines: [String] = []
    @State private var conllRawLines: [String] = []
    @State private var sentsOut: [Sentence] = []
    
    //TODO: what's the diff between these first 2
    @State private var pretokSentsOut: [HashableSentence] = []// input for PretokenisedSentViewSect
    @State private var intermedTokSents: [HashableSentence] = []
    @State var testTokens: [TestToken] = []
    @State var builtSents: [HashableSentence] = []
 
    
    //2 hardcoded sents for testing
    //MARK: data
    @State var pretokSents: [[String]] = [
        ["La"],["capitale"],["italienne"],["est"],["Rome"]
    ] // not used


    @State private var testSentences = ["Aujourd'hui, Paris est la capitale de la France parce qu'à l'époque, c'était la capitale.", "La capitale de l'Allemagne est Berlin, mais avant, c'était Bonn mais on trouvait que c'était pas bon.", "Paris est une grande ville française"]
    @State private var newSentence: String = ""

// if naive, split on space, then on apostrophe IF FR
//button1 naive tokenise, 2 Neural tokenise
    // when tokenised, need form with textfields
    // modified text fields are then taken as input for parsing
    // need sent view :: sent == section, with numbered tokens
    
//
    private var visibleSents: [String] {
        Array(testSentences.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manual entry")
                .font(.title2)
                .bold()

            ForEach(visibleSents, id:\.self){testSentence in
            Text("Input: \"\(testSentence)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            HStack{
                TextField("Additional sentence", text: $newSentence).textFieldStyle(.roundedBorder)
                Button("Add"){
                    if !newSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty{
                        testSentences.append(newSentence)
                        newSentence = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }
//            HStack{
//                Button(action: {runTest(tokType: .retokenise, isRunning: $isRunningRaw)})
//                {
//                ZStack {
//                    Text("Test")
//                        .opacity(isRunningRaw ? 0 : 1)
//                    ProgressView()
//                        .opacity(isRunningRaw ? 1 : 0)
//                }
//                .frame(width: 60, height: 20) // same fixed size as button1, so they stay visually aligned too
//                }
//                .tint(.green)
//                .buttonStyle(.borderedProminent)
//                .disabled(isRunningRaw)
//                
//                
//                Button(action: { runTest(tokType: .conll, isRunning: $isRunningConll) }) {
//                    ZStack {
//                        Text("CoNLL")
//                            .opacity(isRunningConll ? 0 : 1)
//                        ProgressView()
//                            .opacity(isRunningConll ? 1 : 0)
//                    }
//                    .frame(width: 60, height: 20) // same fixed size as button1, so they stay visually aligned too
//                }
//                .tint(.yellow)
//                .buttonStyle(.borderedProminent)
//                .disabled(isRunningConll)
//                
//                
//                Button { // pretokSentsOut = tokenisedInputToSents(input: testSentences) button deactivated for test
//                } label: {
//                    Text("off")
//                }
//                .tint(.orange)
//                .buttonStyle(.borderedProminent)
//                
//                Button {
//                    //use this to parse to pretokenised sents from testSents variable
////                    pretokSentsOut = tokenisedInputToSents(input: testSentences)
//                    //TODO: this crashes as ENsents is absent??
//                    //use this to parse untokenised sents from txt
//                    testSentences = Bundle.main.loadText("ENsents.txt", format: "lines").components(separatedBy: "\n")
//                    // use this to parse from json and get articles, sentences
////                    let decoded: StructureMap = Bundle.main.decode("20minutes_fr_2016_0000_2016.json")
////                    newsArticles = Array(decoded.values)
////                    testSentences = ccSents
//                } label: {
//                    Text("File")
//                }
//                .tint(.cyan)
//                .buttonStyle(.borderedProminent)
//            }

            //MARK: pickers for language, tokenisation method, view
            
            HStack{
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(Language.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.blue)
                Picker("Tokenisation", selection: $currentTokenisationType) {
                    ForEach(TokenisationMethod.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.blue)
            }
            //ProgressBarStylePicker(selection: $progressBarStyle)

            if hasStarted {
                PipelineProgressView(
                    style: progressBarStyle,
                    processed: processedCount,
                    total: totalCount,
                    startTime: startTime,
                    appleProgress: appleProgress
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            let thisSentence = testSentences[0]
            HStack{
                Button {
                    testTokens = applyNaiveTokenisation(language: selectedLanguage, myString: thisSentence
                    )
                } label: {
                Text("Tokenise")
                }
                Spacer()
                Button {
                    let doneSent = makeHashableSentFromTestToks(testTokens: testTokens)
                    if let doneSent{
                        builtSents.append(doneSent)}
                    testTokens = []
                    
                } label: {
                Text("done")
                }

            }
            
            Form{
                ForEach($testTokens, id:\.self) { token in
                    TextField("Token", text: token.form)
//                    Text(token.form)
                        
                    }
                }
            
//            Form{
//                Text("Moo")
//                Text("foo")
//                Text("Bar")
//            }
            
            
//            PretokenisedSentViewSection(pretokSentsOut: pretokSentsOut)
//            OutputLinesViewSection(outputLines: outputLines)
            Spacer()
        }
        .padding()
    }
    func applyNaiveTokenisation(language: Language, myString: String)-> [TestToken]{
        
        let input: String = myString
        var testTokens: [TestToken] = []
        var step1: [Substring] = []
        if language == .FR {
            
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
                
            } // end FR
            
           
        
        if language == .EN {
            step1 = input.split(whereSeparator: { $0 == " "})
        }

        for (num, item) in step1.enumerated() {
            testTokens.append(
                TestToken(id: num, form: String(item))
                                )
        }
        return testTokens
    }
    
    func makeHashableSentFromTestToks(testTokens: [TestToken])-> HashableSentence?{
        guard testTokens.count > 0 else {return nil}
        var keepTokens: [String] = []
        for item in testTokens{
            if item.form != ""{
                keepTokens.append(item.form)
            }
        }
        let returnObject = HashableSentence(id: UUID().uuidString, tokens: keepTokens)
        for x in returnObject.tokens{
            print(x)
        }
        return returnObject
        }
        
    
    
    private func runTest(tokType: TokenisationMethod, isRunning: Binding<Bool>) {
        isRunning.wrappedValue = true
        let tokType: TokenisationMethod = tokType
        errorMessage = nil
        outputLines = []
        conllRawLines = []
        sentsOut = []

        processedCount = 0
        totalCount = 0
        startTime = nil
        hasStarted = true
    
        let inputFile = "\(selectedLanguage)_testConll.txt"
        Task {
            do {
                
                let pipeline = try UDPipeline(languageCode: selectedLanguage.rawValue, treebank: selectedTreebank.short)
                var allSentences: [HashableSentence] = []

                
                //MARK: TOKENISATION and Sentencisation
                switch tokType {
                case .conll:
                    let testlist1: [[String]] = makeConllLinesFromFile(inputFile: inputFile)
                    let intermedSents: [Sentence] = conllLinesToSents(conllLines: testlist1)
//                    var mySents: [TokenisedSentence] = []
                    
                    for sent in intermedSents{
                        let TokSentVers = sent.hashableSentence
                        allSentences.append(TokSentVers)
                    }
                    print("Mysents count = \(allSentences.count)")
//
                    print(allSentences[0])
                case .xml:
                    print("XML")
                    
                    // this works, but builds toksent from source
//                    intermedTokSents  = getSentsForPipelineFromPretokConll(inputFile: inputFile)
//                    for sentence in intermedTokSents{
//                        allSentences.append(sentence)
//                    }
//                    print(allSentences[0])
//                    print("allSentences count = \(allSentences.count)")
                case .retokenise:
                    // Step 1: tokenize everything with model
                    for sentence in testSentences {
                        allSentences.append(contentsOf: try pipeline.tokenize(sentence))
                    }
                    print("Mode a: \(allSentences.count) sents ")
                }
                
                await MainActor.run {
                    totalCount = allSentences.count
                    appleProgress = Progress(totalUnitCount: Int64(max(allSentences.count, 1)))
                    startTime = Date()
                }

                var lines: [String] = []
                var rawLines: [String] = []
                var outSents: [Sentence] = []
                // MARK: Step 2: process sentences
                // process one detected sentence at a time
// >>>>>>>>Limiter here
//                allSentences = allSentences.count > 5 ? Array(allSentences.prefix(5)) : allSentences
                
                for sentence in allSentences {
                    //lines.append("# sent_id = \(sentence.id)") // add meta for view
                    //rawLines.append("# sent_id = \(sentence.id)\n") // add meta for print
                    let tokens = try pipeline.runOnSentence(sentence, level: 5)
                    
                    let mySent: Sentence = Sentence(
                        sentID: sentence.id,
                        conllData: tokens)
                    outSents.append(mySent)
                    lines.append(contentsOf: try pipeline.formatSentence(tokens, mode: "tidy"))
                    rawLines.append(contentsOf: try pipeline.formatSentence(tokens, mode: "raw"))

                    await MainActor.run {
                        processedCount += 1
                        appleProgress.completedUnitCount = Int64(processedCount)
                    }
                }

                try runWriteCoordinator(lines: lines, rawLines: rawLines)
                
                let conllfileuriltest = try printFromConllSents(outsents: outSents)
                
                await MainActor.run {
                    outputLines.append(contentsOf: lines)
                    conllRawLines.append(contentsOf: rawLines)
                    sentsOut.append(contentsOf: outSents)
                    isRunning.wrappedValue = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRunning.wrappedValue = false
                }
            }
        }
    }
    
    

}

#Preview {
    UDPipelineTestView()
}

