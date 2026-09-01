//  NOTA BENE : the preview in XCode and the iPhone Simulator are not perfect: in some circumstances, they show a sentence recognised and tagged as a single token, even though the exact same code builds to a properly-functioning view on a real iPhone.
//
import SwiftUI

struct AllUpUDTestView: View {
    // pre-defined test sentences
    @State private var testSentences = ["Paris est la capitale de la France.", "La capitale de l'Allemagne est Berlin, mais, bon, avant, c'était Bonn."]
    // var for adding user-defined sentences
    @State private var newSentence: String = ""

    // Show only the first 5 sents
    private var visibleSents: [String] {
        Array(testSentences.prefix(5))
    }
    // Output for display (outputLines) or export to file (conllRawLines)
    @State private var outputLines: [String] = []
    @State private var conllRawLines: [String] = []
    
    // time, counters for progress tracking,
    @State private var startTime: Date?
    @State private var processedCount = 0
    @State private var totalCount = 0

    // progress bars: define progressbar, set style, define, initialise the booleans controlling visibility and updating
    @State private var appleProgress = Progress(totalUnitCount: 1)
    @State private var progressBarStyle: ProgressBarStyle = .tqdm
    @State private var hasStarted = false
    @State private var isRunning = false

    // hopefully we won't need the error messsage, but better safe than sorry
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AllUpUDPipeline Test")
                .font(.title2)
                .bold()

            ForEach(visibleSents, id:\.self){testSentence in
            Text("Input: \"\(testSentence)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            TextField("Additional sentence", text: $newSentence)

            HStack{
                Button("Add"){
                    if !newSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty{
                        testSentences.append(newSentence)
                        newSentence = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: runTest) {
                    HStack {
                        Spacer()
                        if isRunning {
                            ProgressView()
                        } else {
                            Text("Test")
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
            }
            
            ProgressBarStylePicker(selection: $progressBarStyle)
            // show the progress bar if it's been started,
            // keep it visible after run complete
            if hasStarted {
                PipelineProgressView(
                    style: progressBarStyle,
                    processed: processedCount,
                    total: totalCount,
                    startTime: startTime,
                    appleProgress: appleProgress
                )
            }
            // show an error message in red if there is one
            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            
            // scrollable view showing the lines of CoNLL-style output
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(outputLines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(Color.gray.opacity(0.08))
            .cornerRadius(8)
            Spacer()
        }
        .padding()
    } // end of the body view

    // function that runs when the `Test` button is pressed
    private func runTest() {
        // ininitalise variables before defining the task
        errorMessage = nil
        outputLines = []
        isRunning = true
        conllRawLines = []
        processedCount = 0
        totalCount = 0
        startTime = nil
        hasStarted = true
        Task {
            do {
                // instantiate the pipeline, and run the tokeniser to make sentences
                let pipeline = try AllUpUDPipeline()
                var allSentences: [TokenisedSentence] = []
                for sentence in testSentences {
                    allSentences.append(contentsOf: try pipeline.tokenize(sentence))
                }
                
                await MainActor.run {
                    // prepaer progress bar
                    totalCount = allSentences.count
                    appleProgress = Progress(totalUnitCount: Int64(max(allSentences.count, 1)))
                    startTime = Date()
                }


                // process sentences one at a time and
                //  update progress bar as each is finished
                var lines: [String] = []
                var rawLines: [String] = []
                for sentence in allSentences {

                    //TODO: very clunky calls here, move methods into `runOnSentence`?
                    // level 5 indicates all levels of annotation
                    // the output is then passed to the formatting methods
                    let tokens = try pipeline.runOnSentence(sentence, level: 5)
                    lines.append(contentsOf: try pipeline.formatSentence(tokens, mode: "tidy"))
                    rawLines.append(contentsOf: try pipeline.formatSentence(tokens, mode: "raw"))

                    await MainActor.run {
                        // get the main actor to update the progress bar
                        processedCount += 1
                        appleProgress.completedUnitCount = Int64(processedCount)
                    }
                }
                // get main actor to get all outputs, toggle bool when done
                await MainActor.run {
                    outputLines.append(contentsOf: lines)
                    conllRawLines.append(contentsOf: rawLines)
                    isRunning = false
                }
            } catch {
                // catch any errors and their description
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRunning = false
                }
            }
        }
    }
}

#Preview {
    AllUpUDTestView()
}
