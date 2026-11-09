
//
//  RNNPipeline.swift
//
//  Runs the converted RNNTagger models sentence by sentence:
//    * <tagger>.mlmodelc            char-level BiLSTM tagger          (convert_rnntagger.py)
//    * <lemma>_encoder.mlmodelc     NMT lemmatiser, encoder           (convert_nmt.py)
//    * <lemma>_decoder_step.mlmodelc NMT lemmatiser, one decoder step (convert_nmt.py)
//  plus the JSON files those scripts wrote (and <tagger>.crf_weights.bin for CRF taggers).
//
//
import Foundation
import Combine
import CoreML
import NaturalLanguage

// MARK: - Metadata written by the conversion scripts

struct RNNTaggerMeta: Codable {
    let wordTruncLen: Int
    let char2ID: [String: Int]
    let id2tag: [String]
    let padID: Int
    let unkID: Int
    let numTags: Int
    let crf: Bool
    let crfBeamSize: Int

    enum CodingKeys: String, CodingKey {
        case wordTruncLen = "word_trunc_len"
        case char2ID
        case id2tag = "ID2tag"
        case padID = "pad_id"
        case unkID = "unk_id"
        case numTags = "num_tags"
        case crf
        case crfBeamSize = "crf_beam_size"
    }
}

struct RNNLemmatizerMeta: Codable {
    let id2src: [String]
    let id2tgt: [String]
    let maxTgtLenFactor: Double
    let decDepth: Int
    let decRNNSize: Int
    let ctxSize: Int

    enum CodingKeys: String, CodingKey {
        case id2src = "ID2src"
        case id2tgt = "ID2tgt"
        case maxTgtLenFactor = "max_tgt_len_factor"
        case decDepth = "dec_depth"
        case decRNNSize = "dec_rnn_size"
        case ctxSize = "ctx_size"
    }
}

/// Which Token column the tagger's tag goes into. Check what your RNNTagger training data contained.
enum RNNTagRole { case upos, xpos, both }

final class RNNPipelineLoader: ObservableObject, PipelineLoader{
    @Published var loadingProgress: Double = min(1.0, 0.0)
    @Published var statusMessage: String = "Waiting to load"
    @Published var loadingComplete: Bool = false
    
    //    var tokenizer: MLModel?
    var taggerModel: MLModel?
    var lemmatizerModel: MLModel?
    var modelArchitecture: ModelArchitecture?
    
    var description: String {
        switch modelArchitecture {
            case .distilbert:
                "DistilBERT based pipeline with WordPiece tokenizer"
            case .rnn:
                "RNNTagger inspired pipeline for POS, LEM"
            case .roberta:
                "XLM-roBERTa based pipeline with SentPiece tokenizer"
            case .camembert:
                "CamemBERT based pipeline with SentPiece tokenizer"
            case .cnnBiLSTM:
                "architectureConflict"
            default:
                "Undetermined as yet, as coming from optional"
        }
    }
    
    var seqLen: Int = 256
    var maxWords: Int = 999
    let runExplicit: Bool = true
    
    init( ){  }
    
    func convertToRealRNNPipe(
        taggerModel: MLModel,
        taggerMeta: RNNTaggerMeta,
        encoderModel: MLModel,
        stepModel: MLModel,
        lemmaMeta: RNNLemmatizerMeta,
        seqLen: Int,
        maxWords: Int,
        languageCode: String,
        treebank: String,
        runExplicitValue: Bool,
        tagRole: RNNTagRole,
        normalizeToNFC: Bool,
        lowercaseLemmaInput: Bool
    ) throws -> RNNPipeline {
        return try RNNPipeline(
            taggerModel: taggerModel,
            taggerMeta: taggerMeta,
            encoderModel: encoderModel,
            stepModel: stepModel,
            lemmaMeta: lemmaMeta,
            tagRole: tagRole,
            normalizeToNFC: normalizeToNFC,
            lowercaseLemmaInput: lowercaseLemmaInput,
            maxWords: maxWords,
            seqLen: 999,
            languageCode: languageCode,
            treebank: treebank,
            runExplicitValue: runExplicit,
        )
    }
    
    
    // MARK: Loading from a folder of compiled models
    @concurrent
    func loadRNNpipeline(
        myConfig: TaggerConfig,
        onProgress: @MainActor @Sendable (Int, String) -> Void
    ) async throws -> RNNPipeline {
        let myConfig: TaggerConfig = myConfig
        let languageCode = myConfig.parsingConfig.selectedLanguage.rawValue
        let treebank = await myConfig.parsingConfig.selectedTreebank.short
        let runExplicit: Bool = myConfig.parsingConfig.runExplicit
        
        
        let tagRole: RNNTagRole = .xpos
        let normalizeToNFC: Bool = true
        let lowercaseLemmaInput: Bool = false
        
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
//        guard let taggerFileName = Bundle.main.url(forResource: "\(languageCode)_rnn_vocab_rnn", withExtension: ".json" ) else {
//            throw PipelineError.LoadingError.resourceMissing("\(languageCode)_rnn_vocab_rnn.json")
//        }
        await onProgress(1, "Loading tagger data")
//        let tagMeta = try await JSONDecoder().decode(RNNTaggerMeta.self, from: Data(contentsOf: taggerFileName))
        let tagMeta: RNNTaggerMeta = try await Bundle.main.safelyDecodeJson("\(languageCode)_rnn_vocab_rnn")
        
        
        await onProgress(2, "Loading lemmatizer data")
//        guard let lemmatizerFileName = Bundle.main.url(forResource: "\(languageCode)_rnn_encoder_vocab_nmt", withExtension: ".json") else {
//            throw PipelineError.LoadingError.resourceMissing("\(languageCode)_rnn_encoder_vocab_nmt.json")
//        }
//        let lemMeta = try await JSONDecoder().decode(RNNLemmatizerMeta.self, from: Data(contentsOf: lemmatizerFileName))
        let lemMeta: RNNLemmatizerMeta = try await Bundle.main.safelyDecodeJson("\(languageCode)_rnn_encoder_vocab_nmt")
        
        await onProgress(3, "Loading tagger model")
        let taggerModel = try await RNNPipelineLoader.loadMlpackage(named: "\(languageCode)_rnn_model_rnn", myConfig: myConfig)
        
        await onProgress(4, "Loading lemmatizer encoder")
        let encoderModel = try await RNNPipelineLoader.loadMlpackage(named: "\(languageCode)_rnn_encoder_nmt", myConfig: myConfig)

        await onProgress(5, "Loading lemmatizer decoder")
        let decoderStepModel = try await RNNPipelineLoader.loadMlpackage(named: "\(languageCode)_rnn_decoder_step_nmt", myConfig: myConfig)
        
        return try await convertToRealRNNPipe(
            taggerModel: taggerModel,
            taggerMeta: tagMeta,
            encoderModel: encoderModel,
            stepModel: decoderStepModel,
            lemmaMeta: lemMeta,
            seqLen: 999,
            maxWords: maxWords,
            languageCode: languageCode,
            treebank: treebank,
            runExplicitValue: runExplicit,
            tagRole: tagRole,
            normalizeToNFC: normalizeToNFC,
            lowercaseLemmaInput: lowercaseLemmaInput,
        )
    }
}


// MARK: - Pipeline
final class RNNPipeline: PipelineHelper, LinguisticProcessingHelper, ObservableObject {
        
        // members mirrored from CNNBiLSTMPipeline, in case PipelineHelper requires them
        var seqLen: Int = 999
        let description = "I'm an RNNTagger + NMT-lemmatiser pipeline"
        let maxWords: Int
        var runExplicit: Bool

    // models and metadata
        let taggerModel: MLModel
        private let encoderModel: MLModel
        private let stepModel: MLModel
        private let taggerMeta: RNNTaggerMeta
        private let lemmaMeta: RNNLemmatizerMeta
        
        // behaviour switches
        private let tagRole: RNNTagRole
        private let normalizeToNFC: Bool           // training data is assumed to be NFC
        private let lowercaseLemmaInput: Bool      // must match how the lemmatiser's source lines were written
//        private let customTokenizer: ((String) throws -> [HashableSentence])?
        
        // lookup tables
        private let charIDs: [UInt32: Int32]       // Unicode scalar -> tagger character ID
        private let padChar: Int32
        private let unkChar: Int32
        private let srcIDs: [String: Int32]        // lemmatiser source symbol -> ID
        private let unkSrc: Int32
        private let boundarySrc: Int32             // the "##" separator
        private let maxSrcLen: Int
        
        // reusable all-zero decoder start state
        private let zeroH: MLMultiArray
        private let zeroC: MLMultiArray
        private let zeroCtx: MLMultiArray
        
        // lemma cache: the same (form, tag) pair always gives the same lemma
        private var lemmaCache: [String: String] = [:]
        private let cacheLock = NSLock()
        
        init(taggerModel: MLModel,
             taggerMeta: RNNTaggerMeta,
             encoderModel: MLModel,
             stepModel: MLModel,
             lemmaMeta: RNNLemmatizerMeta,
             tagRole: RNNTagRole = .upos,
             normalizeToNFC: Bool = true,
             lowercaseLemmaInput: Bool = false,
             //tokenizer: ((String) throws -> [HashableSentence])? = nil,
             maxWords: Int,
             seqLen: Int,
             languageCode: String,
             treebank: String,
             runExplicitValue: Bool

        ) throws {
            var chars: [UInt32: Int32] = [:]
            for (key, value) in taggerMeta.char2ID {
                let scalars = Array(key.unicodeScalars)
                if scalars.count == 1 { chars[scalars[0].value] = Int32(value) }   // skips <UNK>, <PAD>
            }
            
            var src: [String: Int32] = [:]
            for (i, symbol) in lemmaMeta.id2src.enumerated() { src[symbol] = Int32(i) }
            guard let boundary = src["##"] else {
                throw PipelineError.GenericError.unexpectedOutput(
                    "the lemmatiser's source vocabulary has no '##' separator; is this the right model?")
            }
            
            self.taggerModel = taggerModel
            self.encoderModel = encoderModel
            self.stepModel = stepModel
            self.taggerMeta = taggerMeta
            self.lemmaMeta = lemmaMeta
            self.runExplicit = runExplicitValue
            self.tagRole = tagRole
            self.normalizeToNFC = normalizeToNFC
            self.lowercaseLemmaInput = lowercaseLemmaInput
           // self.customTokenizer = tokenizer
            self.charIDs = chars
            self.padChar = Int32(taggerMeta.padID)
            self.unkChar = Int32(taggerMeta.unkID)
            self.srcIDs = src
            self.unkSrc = src["<unk>"] ?? 1
            self.boundarySrc = boundary
            self.seqLen = seqLen
            // limits baked into the converted models (flexible-shape upper bounds)
            self.maxWords = Self.upperBound(of: taggerModel, input: "fwd_char_ids", dimension: 0) ?? 256
            self.maxSrcLen = Self.upperBound(of: encoderModel, input: "src_ids", dimension: 1) ?? 64
            
            self.zeroH = try Self.zeros([lemmaMeta.decDepth, 1, lemmaMeta.decRNNSize])
            self.zeroC = try Self.zeros([lemmaMeta.decDepth, 1, lemmaMeta.decRNNSize])
            self.zeroCtx = try Self.zeros([1, lemmaMeta.ctxSize])
        }
        
        
        
        // MARK: Step 1 -- tokenisation
        
        /// Uses the injected tokenizer if there is one. The default is crude (system sentence splitter, then
        /// words / punctuation by regex) and will NOT match RNNTagger's own tokenisation of its training data.
//        func tokenize(_ text: String) throws -> [HashableSentence] {
//            if let customTokenizer { return try customTokenizer(text) }
//            
//            var sentences: [HashableSentence] = []
//            let splitter = NLTokenizer(unit: .sentence)
//            splitter.string = text
//            splitter.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
//                let tokens = Self.splitTokens(String(text[range]))
//                if !tokens.isEmpty {
//                    sentences.append(HashableSentence(id: String(sentences.count + 1), tokens: tokens, conllMetas: []))
//                }
//                return true
//            }
//            return sentences
//        }
        // change this to perl implementation
        private static let tokenRegex = try! NSRegularExpression(
            pattern: #"[\p{L}\p{M}\p{N}]+(?:['’\-][\p{L}\p{M}\p{N}]+)*|[^\s\p{L}\p{M}\p{N}]"#)
        
        private static func splitTokens(_ sentence: String) -> [String] {
            let ns = sentence as NSString
            return tokenRegex
                .matches(in: sentence, range: NSRange(location: 0, length: ns.length))
                .map { ns.substring(with: $0.range) }
        }
        
        // MARK: Step 2 -- per-sentence processing
        
        /// Same contract as CNNBiLSTMPipeline.runOnSentence. Level 2 = tags, level 3 = lemmas.
        /// RNNTagger has no parser or feature head, so features, heads and relations stay "_".
        func runOnSentence(_ sentence: HashableSentence, myConfig: TaggerConfig) -> OnSentResult {
            if runExplicit { print("running on sents with RNNTagger + NMT pipeline") }
            let wordPieceCount = -5
            guard !sentence.tokens.isEmpty else {
                return OnSentResult(sentence: sentence, subtokCount: wordPieceCount, resultType: .empty, decoded: [])
            }
            guard sentence.tokens.count <= maxWords else {
                return OnSentResult(sentence: sentence, subtokCount: wordPieceCount, resultType: .tooManyWords, decoded: [])
            }
            
            let n = sentence.tokens.count
            let level = myConfig.parsingConfig.maxPipelineStep.rawValue
            var uposTags = Array(repeating: "_", count: n)
            var xposTags = Array(repeating: "_", count: n)
            var lemmas = Array(repeating: "_", count: n)
            
            do {
                if level >= 2 {
                    let tags = try predictTags(for: sentence.tokens)
                    switch tagRole {
                        case .upos: uposTags = tags
                        case .xpos: xposTags = tags
                        case .both: uposTags = tags; xposTags = tags
                    }
                    if level >= 3 {
                        // a nil lemma (word too long, <ood>, empty output) falls back to the word itself
                        lemmas = try zip(sentence.tokens, tags).map { form, tag in
                            try lemma(for: form, tag: tag) ?? form
                        }
                    }
                }
                
                let tokens = (0..<n).map { i in
                    Token(
                        tokid: i + 1,
                        form: sentence.tokens[i],
                        lemma: lemmas[i],
                        upos: uposTags[i],
                        xpos: xposTags[i],
                        feats: "_",
                        head: "_",
                        deprel: "_",
                        col8: "_",
                        col9: "_",
                        subTokens: []
                    )
                }
                return OnSentResult(sentence: sentence, subtokCount: wordPieceCount, resultType: .success, decoded: tokens)
            } catch {
                if runExplicit { print("sentence failed: \(error.localizedDescription)") }
                return OnSentResult(sentence: sentence, subtokCount: wordPieceCount, resultType: .otherError, decoded: [])
            }
        }
        
        // MARK: Tagger
        
        /// One tag string per word. Character windows are built exactly as Data.get_charIDs does.
        private func predictTags(for forms: [String]) throws -> [String] {
            let n = forms.count
            let t = taggerMeta.wordTruncLen
            let fwd = try MLMultiArray(shape: [NSNumber(value: n), NSNumber(value: t)], dataType: .int32)
            let bwd = try MLMultiArray(shape: [NSNumber(value: n), NSNumber(value: t)], dataType: .int32)
            let fs = fwd.strides.map { $0.intValue }
            let bs = bwd.strides.map { $0.intValue }
            let fp = fwd.dataPointer.bindMemory(to: Int32.self, capacity: fwd.count)
            let bp = bwd.dataPointer.bindMemory(to: Int32.self, capacity: bwd.count)
            
            for (i, form) in forms.enumerated() {
                let (f, b) = charWindows(for: form)
                for j in 0..<t {
                    fp[i * fs[0] + j * fs[1]] = f[j]
                    bp[i * bs[0] + j * bs[1]] = b[j]
                }
            }
            
            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "fwd_char_ids": MLFeatureValue(multiArray: fwd),
                "bwd_char_ids": MLFeatureValue(multiArray: bwd),
            ])
            let output = try taggerModel.prediction(from: provider)
            let logits = try BERTpipeHelperStructs.LogitReader(output, "tag_logits", rank: 3, rows: n, labels: taggerMeta.numTags)

            let ids = (0..<n).map { logits.argmax(row: $0) }
            return ids.map { $0 < taggerMeta.id2tag.count ? taggerMeta.id2tag[$0] : "_" }
        }
        
        /// Forward window: the LAST wordTruncLen characters. Backward window: the last wordTruncLen characters of
        /// the REVERSED word (i.e. the first characters of the word, reversed). Both left-padded with PAD.
        /// Iterates Unicode scalars, like Python, not Swift Characters.
        private func charWindows(for word: String) -> (fwd: [Int32], bwd: [Int32]) {
            let t = taggerMeta.wordTruncLen
            let text = normalizeToNFC ? word.precomposedStringWithCanonicalMapping : word
            let ids = text.unicodeScalars.map { charIDs[$0.value] ?? unkChar }
            func window(_ seq: [Int32]) -> [Int32] {
                Array(([Int32](repeating: padChar, count: t) + seq).suffix(t))
            }
            return (window(ids), window(Array(ids.reversed())))
        }
        
        // MARK: Lemmatiser
        
        private func lemma(for form: String, tag: String) throws -> String? {
            let key = form + "\u{1F}" + tag
            cacheLock.lock()
            let hit = lemmaCache[key]
            cacheLock.unlock()
            if let hit { return hit }
            
            guard let result = try generateLemma(form: form, tag: tag) else { return nil }
            
            cacheLock.lock()
            if lemmaCache.count > 100_000 { lemmaCache.removeAll() }
            lemmaCache[key] = result
            cacheLock.unlock()
            return result
        }
        /// note :: RNN lemmatizer so stays here
        /// Source sequence: the letters of the word, "##", the letters of the tag (one symbol per Unicode scalar).
        /// Then run the encoder once and the decoder step greedily, as NMT.translate does.
        private func generateLemma(form: String, tag: String) throws -> String? {
            var text = normalizeToNFC ? form.precomposedStringWithCanonicalMapping : form
            if lowercaseLemmaInput { text = text.lowercased() }
            
            var ids: [Int32] = text.unicodeScalars.map { srcIDs[String($0)] ?? unkSrc }
            ids.append(boundarySrc)
            ids += tag.unicodeScalars.map { srcIDs[String($0)] ?? unkSrc }
            guard ids.count <= maxSrcLen else { return nil }
            
            // encoder, once per word
            let src = try MLMultiArray(shape: [1, NSNumber(value: ids.count)], dataType: .int32)
            let sp = src.dataPointer.bindMemory(to: Int32.self, capacity: src.count)
            let ss = src.strides.map { $0.intValue }
            for (i, id) in ids.enumerated() { sp[i * ss[1]] = id }
            let encOut = try encoderModel.prediction(from: MLDictionaryFeatureProvider(
                dictionary: ["src_ids": MLFeatureValue(multiArray: src)]))
            guard let encRaw = encOut.featureValue(for: "enc_states")?.multiArrayValue else {
                throw PipelineError.ProcessingError.lemmatizationFailed("encoder produced no 'enc_states'")
            }
            let enc = try Self.asFloat32(encRaw)
            
            // decoder loop; start symbol and end symbol are both ID 0
            let prevArray = try MLMultiArray(shape: [1], dataType: .int32)
            let prevPointer = prevArray.dataPointer.bindMemory(to: Int32.self, capacity: 1)
            var prev: Int32 = 0
            var h = zeroH, c = zeroC, ctx = zeroCtx
            var outIDs: [Int] = []
            
            let maxSteps = Int(Double(ids.count) * lemmaMeta.maxTgtLenFactor + 6)
            for _ in 0..<maxSteps {
                prevPointer[0] = prev
                let r = try stepModel.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                    "prev_id": MLFeatureValue(multiArray: prevArray),
                    "enc_states": MLFeatureValue(multiArray: enc),
                    "enc_ctx": MLFeatureValue(multiArray: ctx),
                    "h_in": MLFeatureValue(multiArray: h),
                    "c_in": MLFeatureValue(multiArray: c),
                ]))
                guard let logProbs = r.featureValue(for: "log_probs")?.multiArrayValue,
                      let ctxOut = r.featureValue(for: "ctx_out")?.multiArrayValue,
                      let hOut = r.featureValue(for: "h_out")?.multiArrayValue,
                      let cOut = r.featureValue(for: "c_out")?.multiArrayValue else {
                    throw PipelineError.ProcessingError.lemmatizationFailed("decoder step is missing an output")
                }
                let next = Self.argmaxLastDimension(logProbs)
                if next == 0 { break }
                outIDs.append(next)
                prev = Int32(next)
                ctx = try Self.asFloat32(ctxOut)
                h = try Self.asFloat32(hOut)
                c = try Self.asFloat32(cOut)
            }
            
            let pieces = outIDs.compactMap { $0 < lemmaMeta.id2tgt.count ? lemmaMeta.id2tgt[$0] : nil }
            if pieces.contains("<ood>") { return nil }             // the model says "this input is not a word"
            let lemmaText = pieces.filter { $0 != "<unk>" && $0 != "<pad>" }.joined()
            return lemmaText.isEmpty ? nil : lemmaText
        }
        
        // MARK: Helpers
        
        private static func zeros(_ shape: [Int]) throws -> MLMultiArray {
            let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
            let p = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            for i in 0..<array.count { p[i] = 0 }
            return array
        }
        
        /// Feeding outputs straight back in needs float32. The converter asks for float32 at the interface;
        /// this copy is only a fallback if a model came out as float16.
        private static func asFloat32(_ a: MLMultiArray) throws -> MLMultiArray {
            if a.dataType == .float32 { return a }
            let copy = try MLMultiArray(shape: a.shape, dataType: .float32)
            for i in 0..<a.count { copy[i] = a[i] }
            return copy
        }
        
        /// Index of the largest value along the last dimension of a [1, V] array.
        private static func argmaxLastDimension(_ a: MLMultiArray) -> Int {
            let n = a.shape.last?.intValue ?? 0
            var best = 0
            var bestValue = -Float.infinity
            if a.dataType == .float32, let stride = a.strides.last?.intValue {
                let p = a.dataPointer.bindMemory(to: Float.self, capacity: a.count)
                for k in 0..<n {
                    let v = p[k * stride]
                    if v > bestValue { bestValue = v; best = k }
                }
            } else {
                for k in 0..<n {
                    let v = a[k].floatValue
                    if v > bestValue { bestValue = v; best = k }
                }
            }
            return best
        }
        
        /// Upper bound of a flexible input dimension, read from the converted model.
        private static func upperBound(of model: MLModel, input: String, dimension: Int) -> Int? {
            guard let constraint = model.modelDescription.inputDescriptionsByName[input]?.multiArrayConstraint else {
                return nil
            }
            let shapeConstraint = constraint.shapeConstraint
            switch shapeConstraint.type {
                case .range:
                    let r = shapeConstraint.sizeRangeForDimension[dimension].rangeValue
                    return (r.length > 0 && r.length < 1_000_000) ? r.location + r.length - 1 : nil
                case .enumerated:
                    return shapeConstraint.enumeratedShapes.map { $0[dimension].intValue }.max()
                default:
                    return constraint.shape[dimension].intValue
            }
        }
    
}
