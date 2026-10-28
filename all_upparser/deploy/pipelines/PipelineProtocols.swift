//
//  Custom Protocols and Extensions and Services that pipelines use
//  Tagger
//
//  Created by Adam on 20/10/2026.
//

import Foundation
import CoreML

//MARK: 1 : protocols + extensions
//1 pipeline loader : keep loader stuff separate
protocol PipelineLoader {
}

extension PipelineLoader{
    // loading
    static func loadMlpackage(named name: String, myConfig: TaggerConfig) throws -> MLModel{
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            throw PipelineError.LoadingError.packageLoadFailed(name)
        }
        do {
            switch myConfig.parsingConfig.modelArchitecture {
            case .distilbert:
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                return try MLModel(contentsOf: url, configuration: configuration)
            case .cnnBiLSTM:
                return try MLModel(contentsOf: url)
            }
        } catch {
            throw PipelineError.LoadingError.packageLoadFailed("failed to load model \(name)")
        }
    }
}

// protocol for methods, vars used after pipeline loaded
protocol PipelineHelper {
//    func runOnSentence(_ sentence: HashableSentence, myConfig: TaggerConfig) throws -> [Token]
    func runOnSentence(_ sentence: HashableSentence, myConfig: TaggerConfig) -> OnSentResult
    var description: String { get }
    var maxWords: Int { get }
    
}

// protocol specific to bert-likes for subtoken awareness
protocol SubtokenAwarePipelineHelper: PipelineHelper{
    var seqLen: Int { get }
    
}


// extension defining functs used after pipeline loaded
extension PipelineHelper {
    func tokenize(_ naughtyString: String) -> HashableSentence{
        let input = naughtyString
        let intermediate = input.split(separator: " ")
        let output = intermediate.map {String($0)}
        let outputSent = HashableSentence(id: "e2", tokens: output, conllMetas: [])
        print("this should't have been callable…")
        return outputSent
    }
    // MARK: - Lemma edit-script : functional but not superb lemmatisation
    func applyLemmaRule(form: String, rule: String) -> String {
        var result: String
        if rule == "IDENTITY" {
            result = form.lowercased()
        } else {
            let parts = rule.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let p = Int(parts[0]), let s = Int(parts[1]) else {
                return form
            }
            let middle = String(parts[2])
            let f = Array(form.lowercased())
            if p + s > f.count { return form }
            let prefix = String(f[0..<p])
            let suffix = s > 0 ? String(f[(f.count - s)...]) : ""
            result = prefix + middle + suffix
        }
        if let firstChar = form.first, firstChar.isUppercase {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }
        return result
    }

    // MARK: Dependency parsing
    /// Best tree (Chu-Liu-Edmonds), then the best label for each arc.
    ///
    /// - Parameters:
    ///   - wordCount: number of words; positions are 0 (ROOT) ... wordCount.
    ///   - arcScore: score of `head` as the head of `dependent`.
    ///   - labelScore: score of relation `label` on the arc head -> dependent.
    /// - Returns: one (head, deprel) per word, in word order (ROOT not included).
    func decodeParse(runExplicit: Bool, wordCount: Int,
                     deprelVocab: Vocab,
                     arcScore: (_ dependent: Int, _ head: Int) -> Double,
                     labelScore: (_ label: Int, _ dependent: Int, _ head: Int) -> Double)
        -> [(head: Int, deprel: String)] {
        let n = wordCount + 1
            if runExplicit {
                print("Decoding deps:: raw seq len == \(n)")
            }
            
        // Dense head-score matrix: scoreMatrix[h][d] = score of dependent d attaching to head h.
        // d == 0 (root can't be a dependent) and h == d (a word can't be its own head) are left
        // at -infinity and are never read by the arc-selection loops below.
        // scoreMatrix[head][dependent]; a word can't head itself, and ROOT has no head
        var scoreMatrix = [[Double]](repeating: [Double](repeating: -Double.infinity, count: n), count: n)
        for d in 1..<n {
            for h in 0..<n where h != d {
                scoreMatrix[h][d] = arcScore(d, h)
            }
        }
        let heads = solveArborescence(activeNodes: Array(0..<n), scoreMatrix: scoreMatrix)
        if runExplicit {
            print("heads == \(heads)")
        }

        return (1..<n).map { t in
            // Every non-root node is guaranteed a parent by solveArborescence;
            let head = heads[t] ?? 0 // nil coalesce to be safe
            var bestDeprelId = 0
            var bestDeprelScore = -Double.infinity
            for c in 0..<deprelVocab.itos.count {
                let v = labelScore(c, t, head)
                if v > bestDeprelScore { bestDeprelScore = v; bestDeprelId = c }
            }
            if runExplicit {
                print("Decode deps::\n head ==\(head); deprel===\(deprelVocab.decode(bestDeprelId))")
            }
            return (head: head, deprel: deprelVocab.decode(bestDeprelId))
        }
    }

    // MARK: Chu-Liu-Edmonds maximum spanning arborescence
    /// Solves the maximum-weight spanning arborescence rooted at node 0 over exactly `activeNodes`
    /// (which must include 0), using `scoreMatrix` for edge weights. Returns a map from every
    /// active node except 0 to its chosen parent (also an active node).
    ///
    /// This is a standard recursive implementation of Chu-Liu-Edmonds: greedily pick each node's
    /// best incoming edge; if that produces a cycle, contract the cycle into one representative
    /// node with reweighted edges, recurse on the smaller graph, then expand the result back out.
    /// Recursion terminates because each contraction strictly reduces the number of active nodes,
    /// and a graph with no cycle is returned immediately as-is.
    private func solveArborescence(activeNodes: [Int], scoreMatrix: [[Double]]) -> [Int: Int] {
        // Step 1: each non-root active node's single best incoming edge.
        var bestParent: [Int: Int] = [:]
        for d in activeNodes where d != 0 {
            var best = -Double.infinity
            var bestH = -1
            for h in activeNodes where h != d {
                let s = scoreMatrix[h][d]
                if s > best { best = s; bestH = h }
            }
            bestParent[d] = bestH
        }

        guard let cycle = findCycle(bestParent: bestParent, activeNodes: activeNodes) else {
            // No cycle: the greedy choice is already optimal.
            return bestParent
        }

        // Step 2: contract the cycle into a single representative node (reusing the smallest node id in
        // the cycle, rather than minting a new one, keeps every id a real, meaningful node throughout)
        let cycleSet = Set(cycle)
        let representative = cycle.min()!

        // Total weight of the cycle's own internal edges -- used below to work out true cost of "breaking"
        // the cycle at whichever node ends up accepting an external edge instead.
        var cycleWeight = 0.0
        for v in cycle {
            cycleWeight += scoreMatrix[bestParent[v]!][v]
        }

        let newActiveNodes = activeNodes.filter { !cycleSet.contains($0) || $0 == representative }
        var newScoreMatrix = scoreMatrix

        // Bookkeeping so the contracted-graph result can be expanded back into real node ids afterward
        var enterFrom: [Int: Int] = [:] // u -> which cycle node the (u -> representative) edge really targets
        var exitTo: [Int: Int] = [:]    // w -> which cycle node the (representative -> w) edge really originates from

        for u in activeNodes where !cycleSet.contains(u) {
            var bestIn = -Double.infinity
            var bestVIn = -1
            var bestOut = -Double.infinity
            var bestVOut = -1
            for v in cycle {
                // Incoming: cost of accepting edge (u -> v) instead of v's  current in-cycle edge, while
                // keeping every other cycle edge intact.
                let reweighted = scoreMatrix[u][v] - scoreMatrix[bestParent[v]!][v] + cycleWeight
                if reweighted > bestIn { bestIn = reweighted; bestVIn = v }

                // Outgoing: plain best edge leaving the cycle to u -- no reweighting needed, since
                // which internal edge eventually gets broken doesn't affect edges leaving the cycle.
                let s = scoreMatrix[v][u]
                if s > bestOut { bestOut = s; bestVOut = v }
            }
            newScoreMatrix[u][representative] = bestIn
            enterFrom[u] = bestVIn
            newScoreMatrix[representative][u] = bestOut
            exitTo[u] = bestVOut
        }

        // Step 3: recurse on the smaller, contracted graph.
        let contractedParents = solveArborescence(activeNodes: newActiveNodes, scoreMatrix: newScoreMatrix)

        // Step 4: expand back. Every cycle node keeps its original in-cycle parent, except the one node
        // where an external edge broke the cycle -- that node's real parent is whichever external node
        // fed into the cycle at that point.
        var result = contractedParents
        result.removeValue(forKey: representative)
        for v in cycle {
            result[v] = bestParent[v]
        }
        if let repParent = contractedParents[representative], let breakNode = enterFrom[repParent] {
            result[breakNode] = repParent
        }

        // Any outside node whose contracted parent came out as the representative actually attaches to
        // whichever real cycle node achieved that best exit edge.
        for (node, parent) in contractedParents where parent == representative {
            if let realParent = exitTo[node] {
                result[node] = realParent
            }
        }
        return result
    }

    private func findCycle(bestParent: [Int: Int], activeNodes: [Int]) -> [Int]? {
        var visitedGlobally = Set<Int>()

        for start in activeNodes where start != 0 && !visitedGlobally.contains(start) {
            var path: [Int] = []
            var pathSet = Set<Int>()
            var current = start

            while true {
                if pathSet.contains(current) {
                    let cycleStartIndex = path.firstIndex(of: current)!
                    return Array(path[cycleStartIndex...])
                }
                if visitedGlobally.contains(current) || current == 0 {
                    break // reached root, or a previously-confirmed cycle-free path -- no cycle here
                }
                path.append(current)
                pathSet.insert(current)
                visitedGlobally.insert(current)
                current = bestParent[current]!
            }
        }
        return nil
    }
    
    // formatting output
    // MARK: - Output formatting
    func formatRaw(_ lines: [ConllLineContent]) -> [String] {
        lines.map { line in
            switch line {
            case .row(let tok): return tok.conllRaw
            case .blank: return ""
            }
        }
    }

    /// Use string count to column-align rows of each sent  independently
     func formatTidy(_ lines: [ConllLineContent]) -> [String] {
        var result: [String] = []
        var currentRows: [[String]] = []

        func flushSentence() {
            guard let columnCount = currentRows.first?.count else { return }
            var widths = Array(repeating: 0, count: columnCount)
            for row in currentRows {
                for (i, field) in row.enumerated() {
                    widths[i] = max(widths[i], field.count)
                }
            }
            for row in currentRows {
                let padded = row.enumerated().map { i, field in
                    field.padding(toLength: widths[i], withPad: " ", startingAt: 0)
                }
                result.append(padded.joined(separator: "  "))
            }
            currentRows = []
        }

        for line in lines {
            switch line {
            case .row(let tok):
                currentRows.append([
                    String(tok.tokid), tok.form, tok.lemma, tok.upos,
                    tok.xpos, tok.feats, tok.head, tok.deprel,
                ])
            case .blank:
                flushSentence()
                result.append("")
            }
        }
        flushSentence() // in case the input didn't end with a trailing .blank
        return result
    }

}

// combination of extension: Language and a protocol
// 1. Define a protocol that guarantees availableTBs exists
protocol TreebankProvidable {
    associatedtype TreebankType: Hashable
    var availableTBs: [TreebankType] { get }
    var defaultTB: TreebankType { get } //
}

// 2. Conforming  language enum to it
extension Language: TreebankProvidable {
    typealias TreebankType = Language.Treebank
}

//MARK: 2 : services for pipelines : static functs on Structs used with results
enum PipelineServices {
    struct ResultStorageManager {
        @discardableResult
        static func getRunsDirectory() throws -> URL? {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let runsURL = documents.appendingPathComponent("runs", isDirectory: true)
            
            do {  // Automatically creates the folder if it's missing
                try FileManager.default.createDirectory(at: runsURL, withIntermediateDirectories: true, attributes: nil)
                return runsURL
            } catch {
                print("Failed to create 'runs' directory: \(error)")
                throw PipelineError.ExportError.outputFolderCreationError
            }
        }
        // save run data in sandbox
        static func saveRun(_ runOutput: RunOutput) throws ->URL? {
            guard let runsFolder = try getRunsDirectory() else { throw PipelineError.ExportError.outputFolderCreationError }
            let fileURL = runsFolder.appendingPathComponent("\(runOutput.id).json")
            
            do {
                let data = try JSONEncoder().encode(runOutput)
                try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
                print("Successfully saved to: \(fileURL.path)")
                return fileURL
            } catch {
                print("Failed to save result: \(error)")
                throw PipelineError.ExportError.fileSaveError(filename: fileURL.absoluteString)
            }
        }
        
        static func loadRun(runID: String) throws -> RunOutput? {
            guard let runsFolder = try getRunsDirectory() else { throw PipelineError.ExportError.outputFolderCreationError }
            let fileURL = runsFolder.appendingPathComponent("\(runID).json")
            
            do {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder().decode(RunOutput.self, from: data)
            } catch {
                print("Failed to load result: \(error)")
                return nil
            }
        }
    }
    struct ExporterService {
        /// Writes processing output string directly to a user-selected folder URL
        static func exportDataToFile(
            exportContent: String,
            customName: String,
            targetFolderURL: URL,
            exportFormat: ExportFormat,
            runExplicit: Bool
            
        ) throws -> URL {
            let fileExtension = exportFormat.fileExtension
            
            if runExplicit{
                print("step1 success")
            }
            // 2. Format sanitized filename
            var safeName = customName.sanitizedFileName
            if !safeName.hasSuffix(".\(fileExtension)") {
                safeName += ".\(fileExtension)"
            }
            if runExplicit{
                print(safeName)
                print("step2 success")
            }
            // 3. Construct destination path inside the chosen directory
            // if target dir is the default dir, need to allow access
            
            //new func here, returning folder URL with privileges
            let safeTargetFolderURL = try resolveOutputDir(targetFolderURL: targetFolderURL)
            let destinationFileURL = safeTargetFolderURL.appendingPathComponent(safeName)
            

            
            // 4. Elevate security permissions for external directory write
            if runExplicit{
                
                print("step3 success:: -> \(destinationFileURL)")
            }
            // 4. Elevate security permissions for external directory write
            let gotAccess = safeTargetFolderURL.startAccessingSecurityScopedResource()
            defer {
                if gotAccess {
                        targetFolderURL.stopAccessingSecurityScopedResource()
                    if runExplicit { print("step4 gotAccess == \(gotAccess)") }
                }
            }
            
            // 5. Write
            try exportContent.write(to: destinationFileURL, atomically: true, encoding: .utf8)
            if runExplicit{
                print("step5 success URL == \(destinationFileURL.path())")
            }
            return destinationFileURL
        }
        

        static func resolveOutputDir(targetFolderURL: URL) throws -> URL {
            let defaults = UserDefaults.standard

            // Not the saved default (new choice, or nothing saved yet), or no bookmark to resolve:
            // use the URL as given.
            guard let savedDefault = defaults.url(forKey: StoreKey.outputDir),
                  targetFolderURL.normalizedDir == savedDefault.normalizedDir,
                  let data = defaults.data(forKey: StoreKey.outputBookmark)
            else {
                return targetFolderURL
            }

            var stale = false
            do {
                let url = try URL(resolvingBookmarkData: data,
                                  options: [],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale)
                if stale, url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let fresh = try? url.bookmarkData(options: [],
                                                         includingResourceValuesForKeys: nil,
                                                         relativeTo: nil) {
                        defaults.set(fresh, forKey: StoreKey.outputBookmark)
                    }
                }
                return url
            } catch {
                defaults.removeObject(forKey: StoreKey.outputBookmark)
                throw PipelineError.ExportError.outputFolderCreationError
            }
        }
    
    }
}

