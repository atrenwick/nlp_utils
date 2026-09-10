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

//TODO: A-B choices for tokenisation method, source type, sourcelang
//TODO: output conll : change to std, grid ; std needs to have \t
//TODO: parse from file rather than bundle
//TODO: export, share parsed output

enum TokenisationMethod: String, CaseIterable, Identifiable {
    var id: Self {self}
    case conll
//    case naive
    case retokenise
}

struct UDPipelineTestView: View {
    //2 hardcoded sents for testing
    //MARK: data
    @State private var testSentences = ["Paris est la capitale de la France.", "La capitale de l'Allemagne est Berlin, mais avant, c'était Bonn mais on trouvait que c'était pas bon.", "Paris est une grande ville française"]
    @State var pretokSents: [[String]] = [
        ["La"],["capitale"],["italienne"],["est"],["Rome"]
    ] // not used
    @State private var newSentence: String = ""

    //MARK: settings changed via UI
    @State private var selectedLanguage: LanguageCode = .FR
    @State private var currentTokenisationType: TokenisationMethod = .conll
    @State private var selectedTreebank: Language.Treebank = .enTB1

    @State private var progressBarStyle: ProgressBarStyle = .tqdm
    
    //MARK: progresstracking vars
    @State private var errorMessage: String?
    @State private var isRunningConll = false
    @State private var isRunningRaw = false
    @State private var processedCount = 0
    @State private var totalCount = 0
    @State private var startTime: Date?
    @State private var appleProgress = Progress(totalUnitCount: 1)
    @State private var hasStarted = false
    
    //MARK: vars for intermediate states and outputs
    @State private var outputLines: [String] = []
    @State private var conllRawLines: [String] = []
    @State private var conllSentsOut: [ConllSent] = []
    
    //TODO: what's the diff between these first 2
    @State private var pretokSentsOut: [TokenisedSentence] = []// input for PretokenisedSentViewSect
    @State private var intermedTokSents: [TokenisedSentence] = []

    private var visibleSents: [String] {
        Array(testSentences.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Parsing Test: Settings")
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
            HStack{
                Button(action: {runTest(tokType: .retokenise, isRunning: $isRunningRaw)})
                {
                ZStack {
                    Text("Test")
                        .opacity(isRunningRaw ? 0 : 1)
                    ProgressView()
                        .opacity(isRunningRaw ? 1 : 0)
                }
                .frame(width: 60, height: 20) // same fixed size as button1, so they stay visually aligned too
                }
                .tint(.green)
                .buttonStyle(.borderedProminent)
                .disabled(isRunningRaw)
                
                
                Button(action: { runTest(tokType: .conll, isRunning: $isRunningConll) }) {
                    ZStack {
                        Text("CoNLL")
                            .opacity(isRunningConll ? 0 : 1)
                        ProgressView()
                            .opacity(isRunningConll ? 1 : 0)
                    }
                    .frame(width: 60, height: 20) // same fixed size as button1, so they stay visually aligned too
                }
                .tint(.yellow)
                .buttonStyle(.borderedProminent)
                .disabled(isRunningConll)
                
                
                Button { // pretokSentsOut = tokenisedInputToSents(input: testSentences) button deactivated for test
                } label: {
                    Text("off")
                }
                .tint(.orange)
                .buttonStyle(.borderedProminent)
                
                Button {
                    //use this to parse to pretokenised sents from testSents variable
//                    pretokSentsOut = tokenisedInputToSents(input: testSentences)
                    //TODO: this crashes as ENsents is absent??
                    //use this to parse untokenised sents from txt
                    testSentences = Bundle.main.loadText("ENsents.txt", format: "lines").components(separatedBy: "\n")
                    // use this to parse from json and get articles, sentences
//                    let decoded: StructureMap = Bundle.main.decode("20minutes_fr_2016_0000_2016.json")
//                    newsArticles = Array(decoded.values)
//                    testSentences = ccSents
                } label: {
                    Text("File")
                }
                .tint(.cyan)
                .buttonStyle(.borderedProminent)
            }

            //MARK: pickers for language, tokenisation method, view
            HStack{
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(LanguageCode.allCases) { mode in
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
            ProgressBarStylePicker(selection: $progressBarStyle)

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

            PretokenisedSentViewSection(pretokSentsOut: pretokSentsOut)
            OutputLinesViewSection(outputLines: outputLines)
            Spacer()
        }
        .padding()
    }
    
    
    private func runTest(tokType: TokenisationMethod, isRunning: Binding<Bool>) {
        isRunning.wrappedValue = true
        let tokType: TokenisationMethod = tokType
        errorMessage = nil
        outputLines = []
        conllRawLines = []
        conllSentsOut = []

        processedCount = 0
        totalCount = 0
        startTime = nil
        hasStarted = true
    
        let inputFile = "\(selectedLanguage)_testConll.txt"
        Task {
            do {
                
                let pipeline = try UDPipeline(languageCode: selectedLanguage.rawValue, treebank: selectedTreebank.short)
                var allSentences: [TokenisedSentence] = []

                
                //MARK: TOKENISATION and Sentencisation
                switch tokType {
                case .conll:
                    let testlist1: [[String]] = makeConllLinesFromFile(inputFile: inputFile)
                    let intermedSents: [ConllSent] = makeConllSent(conllLines: testlist1)
//                    var mySents: [TokenisedSentence] = []
                    
                    for sent in intermedSents{
                        let TokSentVers = sent.sentAsTokenisedSentence
                        allSentences.append(TokSentVers)
                    }
                    print("Mysents count = \(allSentences.count)")
//
                    print(allSentences[0])

                    
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
                var outSents: [ConllSent] = []
                // MARK: Step 2: process sentences
                // process one detected sentence at a time
// >>>>>>>>Limiter here
//                allSentences = allSentences.count > 5 ? Array(allSentences.prefix(5)) : allSentences
                
                for sentence in allSentences {
                    //lines.append("# sent_id = \(sentence.id)") // add meta for view
                    //rawLines.append("# sent_id = \(sentence.id)\n") // add meta for print
                    let tokens = try pipeline.runOnSentence(sentence, level: 5)
                    
                    let mySent: ConllSent = ConllSent(
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
                    conllSentsOut.append(contentsOf: outSents)
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

