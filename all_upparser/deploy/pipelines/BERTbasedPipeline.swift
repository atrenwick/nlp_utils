//
//  BERTbasedPipeline.swift
//  Tagger
//
//  Created by Adam on 18/10/2026.
//

import Foundation
import CoreML
import SwiftUI
import Combine

class BERTlikePipelineLoader: ObservableObject, PipelineLoader{
    @Published var loadingProgress: Double = min(1.0, 0.0)
    @Published var statusMessage: String = "Waiting to load..."
    @Published var loadingComplete: Bool = false
    
    var wordPieceTokenizer: WordPieceTokenizer?
    var taggerModel: MLModel?
    var labels: BERTpipeHelpers.LabelVocabsForBERTlike?
    let description: String = "BERTlikePipeline"
    
    /// fixed lengths the model was converted with, loaded from model for safety
    var seqLen: Int = 512
    var maxWords: Int = 192
    let runExplicit: Bool = true
    
    // super lightweight init
    init(){
    }
    
    func convertToRealPipeline(
        wordPieceTokenizer: WordPieceTokenizer,
        taggerModel: MLModel,
        labels: BERTpipeHelpers.LabelVocabsForBERTlike,
        seqLen: Int,
        maxWords: Int,
        languageCode: String,
        treebank: String,
        runExplicitValue: Bool
    ) throws -> BERTlikePipeline {
        print("calling converter")
        return BERTlikePipeline(
            taggerModel: taggerModel,
            wordPieceTokenizer: wordPieceTokenizer,
            labels: labels,
            seqLen: seqLen,
            maxWords: maxWords,
            runExplicitValue: runExplicitValue
        )
    }
    
    @concurrent
    func loadBERTlikePipe(
        myConfig: TaggerConfig,
        onProgress: @MainActor @Sendable (Int, String) -> Void
    ) async throws -> BERTlikePipeline {
        let myConfig: TaggerConfig = myConfig
        let vX = "v2"
        let languageCode = myConfig.parsingConfig.selectedLanguage.rawValue
        let treebank = await myConfig.parsingConfig.selectedTreebank.short
        let runExplicitValue: Bool = myConfig.parsingConfig.runExplicit
        print("loading on main thread:", Thread.isMainThread)
        
        let wordPieceTokenizer: WordPieceTokenizer?
        let taggerModel: MLModel?
        let labels: BERTpipeHelpers.LabelVocabsForBERTlike?
        var seqLen: Int?
        var maxWords: Int?
        // tokenizer model
        
        await onProgress(1, "Load vocabs")
        labels = try await BERTpipeHelpers.LabelVocabsForBERTlike.loadLabelVocabularies(languageCode: languageCode, treebank: treebank, vx: vX)
        
        await onProgress(2, "Load wordpiece tokenizer")
        wordPieceTokenizer = try await WordPieceTokenizer.fromBundle(languageCode: languageCode, treebank: treebank, vx: vX)
        
        await onProgress(3, "Load tagger model")
        taggerModel = try await BERTlikePipeline.loadMlpackage(named: "\(languageCode)_distilbert_tagger_parser_\(treebank)\(vX)", myConfig: myConfig)
        
        await onProgress(4, "Verifying settings")
        
        if let tmodel = taggerModel{
            let limits = try await Self.limits(of: tmodel)
            seqLen = limits.seqLen
            maxWords = limits.maxWords
        }
        
        guard
            let wordPieceTokenizer = wordPieceTokenizer, let taggerModel = taggerModel, let labels = labels, let seqLen = seqLen, let maxWords = maxWords else { throw PipelineError.ConfigurationError.notReadyToSendToRunner }
        return try await convertToRealPipeline(
            wordPieceTokenizer: wordPieceTokenizer,
            taggerModel: taggerModel,
            labels: labels,
            seqLen: seqLen,
            maxWords: maxWords,
            languageCode: languageCode,
            treebank: treebank,
            runExplicitValue: runExplicitValue
        )
    }
    /// seqLen and maxWords are the second dimension of the two [1, N] inputs.
    private static func limits(of model: MLModel) throws -> (seqLen: Int, maxWords: Int) {
        func length(of input: String) throws -> Int {
            guard let shape = model.modelDescription.inputDescriptionsByName[input]?
                .multiArrayConstraint?.shape, shape.count == 2 else {
                throw PipelineError.ConfigurationError.invalidModelInputs("\(input) isn't a [1, N] array input")
            }
            return shape[1].intValue
        }
        let seqLen = try length(of: "input_ids")
        let maxWords = try length(of: "word_index")
        guard maxWords <= seqLen - 1 else {
            throw PipelineError.ConfigurationError.invalidModelInputs(
                "word_index length \(maxWords) must be at most input_ids length \(seqLen) - 1")
        }
        return (seqLen, maxWords)
    }
    /// convert id -> label as string.
    private static func label(_ vocab: Vocab, _ id: Int) -> String { vocab.decode(id) }
}

final class BERTlikePipeline: PipelineHelper, SubtokenAwarePipelineHelper,PipelineLoader {
    private let taggerModel: MLModel
    let labels: BERTpipeHelpers.LabelVocabsForBERTlike
    let description: String = "BERTlikePipeline"

    /// fixed lengths the model was converted with, loaded from model for safety
    let wordPieceTokenizer: WordPieceTokenizer
    let seqLen: Int
    let maxWords: Int
    let runExplicit: Bool
    
    init(
        taggerModel: MLModel,
        wordPieceTokenizer: WordPieceTokenizer,
        labels: BERTpipeHelpers.LabelVocabsForBERTlike,
        seqLen: Int,
        maxWords: Int,
        runExplicitValue: Bool,
    )  {
        self.taggerModel = taggerModel
        self.wordPieceTokenizer = wordPieceTokenizer
        self.labels = labels
        self.seqLen = seqLen
        self.maxWords = maxWords
        self.runExplicit = runExplicitValue
        
    }
    func runOnSentence(_ sentence: HashableSentence, myConfig: TaggerConfig) -> OnSentResult {
        if runExplicit { print("running on sents with bert pipeline") }

        guard !sentence.tokens.isEmpty else {
            return OnSentResult(sentence: sentence, resultType: .empty, decoded: [])
        }
        // maxWords counts the ROOT slot, so the most real words allowed is maxWords - 1
        guard sentence.tokens.count < maxWords else {
            return OnSentResult(sentence: sentence, resultType: .tooManyWords, decoded: [])
        }

        var wordPieceTokenizer = self.wordPieceTokenizer                  // a copy; the vocabulary isn't duplicated
        wordPieceTokenizer.showWordPieces = myConfig.exportConfig.getsubtokens
        var currentWordpieceCount: Int = -3
        do {
            guard let encoded = try wordPieceTokenizer.encode(words: sentence.tokens, seqLen: seqLen, maxWords: maxWords
                ) else {
                return OnSentResult(sentence: sentence, resultType: .otherError, decoded: [])
            }
            currentWordpieceCount = encoded.wordPieces?.count ?? -4
            let output = try predict(encoded)
            let decoded = try decode(output, words: sentence.tokens, wordPieces: encoded.wordPieces)
            return OnSentResult(sentence: sentence,  subtokCount: currentWordpieceCount, resultType: .success, decoded: decoded)
        } catch WordPieceError.tooManySubwords {
            return OnSentResult(sentence: sentence,  subtokCount: currentWordpieceCount, resultType: .tooManySubtoks, decoded: [])
        } catch WordPieceError.tooManyWords {                              // backstop; the guard above catches this first
            return OnSentResult(sentence: sentence, resultType: .tooManyWords, decoded: [])
        } catch {
            if runExplicit { print("sentence failed: \(error.localizedDescription)") }
            return OnSentResult(sentence: sentence, resultType: .otherError, decoded: [])
        }
    }
    
    
    // MARK: Running the model
     func predict(_ encoded: WordPieceEncodedSentence) throws -> MLFeatureProvider {
        let arrays = try encoded.multiArrays()
        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: arrays.inputIDs),
            "word_index": MLFeatureValue(multiArray: arrays.wordIndex),
        ])
        do {
            return try taggerModel.prediction(from: inputs)
        } catch {
            throw PipelineError.ProcessingError.predictionFailed(error)
        }
    }
    // MARK: Decoding
     func decode(_ output: MLFeatureProvider, words: [String],
                        wordPieces: [[String]]?) throws -> [Token] {
        /// 6 padded output tensors -> labelled tokens. Only the first (words + 1) cols mean anything, rest is PAD
        let n = words.count + 1
        let upos = try BERTpipeHelpers.LogitReaderForBERTlike(output, "upos_logits", rank: 3, rows: n, labels: labels.upos.itos.count)
        let feats = try BERTpipeHelpers.LogitReaderForBERTlike(output, "feats_logits", rank: 3, rows: n, labels: labels.feats.itos.count)
        let lemmaRules = try BERTpipeHelpers.LogitReaderForBERTlike(output, "lemma_rule_logits", rank: 3, rows: n,
                                         labels: labels.lemmaRule.itos.count)
        let arc = try BERTpipeHelpers.LogitReaderForBERTlike(output, "arc_logits", rank: 3, rows: n)
        let deprels = try BERTpipeHelpers.LogitReaderForBERTlike(output, "label_logits", rank: 4, rows: n,
                                      labels: labels.deprel.itos.count)

        // deprel, head decoding
        let parse = decodeParse(
            runExplicit: true,
            wordCount: words.count,
            deprelVocab: labels.deprel,
            arcScore: { dependent, head in Double(arc.value(row: dependent, column: head)) },
            labelScore: { label, dependent, head in
                Double(deprels.value(channel: label, row: dependent, column: head))
            }
        )
        
        guard parse.count == words.count else {
            throw PipelineError.GenericError.unexpectedOutput(
                "parse decoder returned \(parse.count) (head, deprel) pairs for \(words.count) words")
        }
        var tokens: [Token] = []
        tokens.reserveCapacity(words.count)
        for i in 1..<n {
            let form = words[i - 1]
            let rule = labels.lemmaRule.decode(lemmaRules.argmax(row: i))
            tokens.append(Token(
                tokid: i,
                form: form,
                lemma: applyLemmaRule(form: form, rule: rule),
                upos: labels.upos.decode(upos.argmax(row: i)),
                xpos: "_",
                feats: labels.feats.decode(feats.argmax(row: i)),
                head: String(parse[i - 1].head),
                deprel: parse[i - 1].deprel,
                col8: "_",
                col9: "_",
                subTokens: wordPieces?[i - 1]
            ))
            if runExplicit{
                var subels: String = "empty"
                let tidy1 = wordPieces?[i-1]
                if let success = tidy1{
                    subels = success.joined(separator: "/")
                }
                print("\(form) :: \(subels)")
            }
        }
        return tokens
    }
}


enum BERTpipeHelpers{
    struct LabelVocabsForBERTlike {
    // MARK: - Label vocabularies for BERT derived models :: 4x vocabs with loader
    /// The  vocabularies that turn output indices back into labels, from same training as model
    /// these are not the same as for BiLSTM models
        let upos: Vocab
        let feats: Vocab
        let deprel: Vocab
        let lemmaRule: Vocab
        
        static func loadLabelVocabularies(languageCode: String,
                                          treebank: String,
                                          bundle: Bundle = .main,
                                          vx: String
        ) throws -> LabelVocabsForBERTlike {
            
            func vocab(_ label: String, vx: String) throws -> Vocab {
                let name = "\(languageCode)_distilbert_\(label)_vocab_\(treebank)\(vx)"
                guard let url = bundle.url(forResource: name, withExtension: "json") else {
                    throw PipelineError.GenericError.missingResource("\(name).json")
                }
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(VocabData.self, from: data)
                return Vocab(data: decoded)
            }

            return LabelVocabsForBERTlike(
                upos: try vocab("upos", vx: vx),
                feats: try vocab("feats", vx: vx),
                deprel: try vocab("deprel", vx: vx),
                lemmaRule: try vocab("lemma_rule", vx: vx)
            )
        }
    }
    
    struct LogitReaderForBERTlike {
    // MARK: - Reading Core ML output arrays for bert-derived models to deal with padding
    /// Reads values out of an MLMultiArray without boxing every element. Honours the array's
    /// strides (Core ML may pad rows) and its element type (the model's outputs are normally
    /// float16; float32 and double are handled too).

        private let array: MLMultiArray             // keeps the buffer alive
        private let base: UnsafeRawPointer
        private let dataType: MLMultiArrayDataType
        private let strides: [Int]
        private let shape: [Int]

        /// - Parameters:
        ///   - rank: expected number of dimensions (3 = [1, rows, width], 4 = [1, channels, rows, columns])
        ///   - rows: how many rows the caller will read (words + 1)
        ///   - labels: the vocabulary size this array's label dimension must match (nil to skip)
        init(_ output: MLFeatureProvider, _ name: String, rank: Int, rows: Int,
             labels: Int? = nil) throws  {
            guard let array = output.featureValue(for: name)?.multiArrayValue else {
                throw PipelineError.GenericError.unexpectedOutput("\(name) is missing")
            }

            let shape = array.shape.map { $0.intValue }
            guard shape.count == rank, shape[rank - 2] >= rows else {
                throw PipelineError.GenericError.unexpectedOutput("\(name) has shape \(shape); expected rank \(rank) with at least \(rows) rows")
            }
            if let labels {
                let width = rank == 3 ? shape[2] : shape[1]
                guard width == labels else {
                    throw PipelineError.GenericError.unexpectedOutput("\(name) has \(width) labels but the vocabulary has \(labels); the vocabulary files and the model are from different training runs")
                }
            }
           switch array.dataType {
            case .float16, .float32, .double: break
           default: throw PipelineError.GenericError.unexpectedOutput("\(name) has an unsupported element type")
            }
            self.array = array
            self.base = UnsafeRawPointer(array.dataPointer)
            self.dataType = array.dataType
            self.strides = array.strides.map { $0.intValue }
            self.shape = shape
        }

        /// rank 3: value at [0, row, column]
        func value(row: Int, column: Int) -> Float {
            load(strides[1] * row + strides[2] * column)
        }

        /// rank 3: index of the largest value in a row (over the last dimension)
        func argmax(row: Int) -> Int {
            var best = 0
            var bestValue = -Float.infinity
            for k in 0..<shape[2] {
                let v = value(row: row, column: k)
                if v > bestValue { bestValue = v; best = k }
            }
            return best
        }

        /// rank 4 ([1, channels, rows, columns]): value at [0, channel, row, column]
        func value(channel: Int, row: Int, column: Int) -> Float {
            load(strides[1] * channel + strides[2] * row + strides[3] * column)
        }

        private func load(_ offset: Int) -> Float {
            switch dataType {
            case .float32:
                return base.load(fromByteOffset: offset * 4, as: Float.self)
            case .double:
                return Float(base.load(fromByteOffset: offset * 8, as: Double.self))
            default:                                    // .float16, checked in init
                return Self.float(fromHalfBits: base.load(fromByteOffset: offset * 2, as: UInt16.self))
            }
        }

        /// IEEE half -> Float by bit manipulation, so no Float16 type is needed (it isn't
        /// available when building for Intel simulators).
        private static func float(fromHalfBits h: UInt16) -> Float {
            let sign = UInt32(h >> 15) << 31
            let exponent = UInt32((h >> 10) & 0x1F)
            let mantissa = UInt32(h & 0x3FF)
            switch exponent {
            case 0:
                let magnitude = Float(mantissa) / 16_777_216        // subnormal (or zero): mantissa * 2^-24
                return sign == 0 ? magnitude : -magnitude
            case 0x1F:
                return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13))   // infinity / NaN
            default:
                return Float(bitPattern: sign | ((exponent + 112) << 23) | (mantissa << 13))
            }
        }
    }

    
}
