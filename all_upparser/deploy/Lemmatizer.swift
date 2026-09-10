//
//  Lemmatizer.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
//
import Foundation
import CoreML



enum LemmatizerError: Error {
    case modelLoadFailed(String)
    case resourceMissing(String)
    case unknownChar(Character)
}

struct LemmaVocabs: Codable {
    let char: [String]
    let upos: [String]
}



//MARK: lemmatizer runner :
//TODO: change hardcoded paths >>>> forResource <<<< when EN model trained
final class LemmatizerRunner {

    private let encoder: MLModel
    private let decoderStep: MLModel

    private let charStoi: [String: Int]
    private let charItos: [String]
    private let uposStoi: [String: Int]

    private let padId: Int
    private let unkId: Int
    private let bosId: Int
    private let eosId: Int

    private let lemmaDict: [String: String]

    private let maxLemmaLen = 32    // Must match MAX_SRC_LEN in convert_lemmatizer.py :: 32 for FR, 40 for EN
    private let maxSrcLen = 32 // :: 32 for FR, 40 for EN

    init(languageCode: String) throws {
        guard let encoderURL = Bundle.main.url(forResource: "\(languageCode)_neuralLemmatizerEncoder", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "\(languageCode)_neuralLemmatizerEncoder", withExtension: "mlpackage") else {
            throw LemmatizerError.resourceMissing("\(languageCode)_neuralLemmatizerEncoder")
        }
        guard let decoderURL = Bundle.main.url(forResource: "\(languageCode)_neuralLemmatizerDecoderStep", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "\(languageCode)_neuralLemmatizerDecoderStep", withExtension: "mlpackage") else {
            throw LemmatizerError.resourceMissing("\(languageCode)_neuralLemmatizerDecoderStep")
        }

        do {
            self.encoder = try MLModel(contentsOf: encoderURL)
            self.decoderStep = try MLModel(contentsOf: decoderURL)
        } catch {
            throw LemmatizerError.modelLoadFailed(error.localizedDescription)
        }

        // --- Load vocabularies -------------------------------------------------
        guard let vocabsURL = Bundle.main.url(forResource: "\(languageCode)_neurallemma_vocabs", withExtension: "json") else {
            throw LemmatizerError.resourceMissing("\(languageCode)_neurallemma_vocabs.json")
        }
        let vocabsData = try Data(contentsOf: vocabsURL)
        let vocabs = try JSONDecoder().decode(LemmaVocabs.self, from: vocabsData)

        self.charItos = vocabs.char
        var cs: [String: Int] = [:]
        for (i, c) in vocabs.char.enumerated() { cs[c] = i }
        self.charStoi = cs

        var us: [String: Int] = [:]
        for (i, u) in vocabs.upos.enumerated() { us[u] = i }
        self.uposStoi = us

        self.padId = cs["<pad>"] ?? 0
        self.unkId = cs["<unk>"] ?? 1
        self.bosId = cs["<bos>"] ?? 2
        self.eosId = cs["<eos>"] ?? 3

        // --- Load the frequency dictionary --------------------------------------
        guard let dictURL = Bundle.main.url(forResource: "\(languageCode)_neurallemma_dict", withExtension: "json") else {
            throw LemmatizerError.resourceMissing("\(languageCode)_neurallemma_dict.json")
        }
        let dictData = try Data(contentsOf: dictURL)
        self.lemmaDict = try JSONDecoder().decode([String: String].self, from: dictData)
    }

    /// Look up or predict the lemma for a single (form, UPOS) pair.
    func lemmatize(form: String, upos: String) throws -> String {
        let key = "\(form.lowercased())|\(upos)"
        if let dictLemma = lemmaDict[key] {
            return dictLemma
//            return "\(dictLemma)_zb" tempDeactivate// option to add zb to show provenance of lemmas
        }
        return try neuralLemmatize(form: form, upos: upos)
    }

    /// Convenience for a whole sentence at once.
    func lemmatize(forms: [String], uposTags: [String]) throws -> [String] {
        precondition(forms.count == uposTags.count, "forms and uposTags must be the same length")
        return try zip(forms, uposTags).map { try lemmatize(form: $0, upos: $1) }
    }

    // ------------------------------------------------------------------------
    // Neural fallback: run the encoder once, then loop the decoder step.
    // ------------------------------------------------------------------------

    private func neuralLemmatize(form: String, upos: String) throws -> String {
        let rawIds = try form.lowercased().map { char -> Int in
            let s = String(char)
            guard let id = charStoi[s] else { return unkId }
            return id
        }
        guard !rawIds.isEmpty else { return form }

        // Pad/truncate to `convert_lemmatizer.py`'s MAX_SRC_LEN
        let realLen = min(rawIds.count, maxSrcLen)
        var srcIds = Array(rawIds.prefix(maxSrcLen))
        while srcIds.count < maxSrcLen { srcIds.append(padId) }

        let uposId = uposStoi[upos] ?? 0

        // --- Encoder pass ----------------------------------------------------
        let srcArray = try MLMultiArray(shape: [1, NSNumber(value: maxSrcLen)], dataType: .int32)
        for (i, id) in srcIds.enumerated() { srcArray[[0, i] as [NSNumber]] = NSNumber(value: id) }

        let maskArray = try MLMultiArray(shape: [1, NSNumber(value: maxSrcLen)], dataType: .int32)
        for i in 0..<maxSrcLen {
            maskArray[[0, i] as [NSNumber]] = NSNumber(value: i < realLen ? 1 : 0)
        }

        let uposArray = try MLMultiArray(shape: [1], dataType: .int32)
        uposArray[[0] as [NSNumber]] = NSNumber(value: uposId)

        let encoderInput = try MLDictionaryFeatureProvider(dictionary: [
            "src": srcArray,
            "mask": maskArray,
            "upos": uposArray,
        ])
        let encoderOutput = try encoder.prediction(from: encoderInput)

        guard let encOut = encoderOutput.featureValue(for: "enc_out")?.multiArrayValue,
              var h = encoderOutput.featureValue(for: "init_h")?.multiArrayValue,
              var c = encoderOutput.featureValue(for: "init_c")?.multiArrayValue else {
            throw LemmatizerError.modelLoadFailed("encoder output missing expected fields:: see func neuralLemmatize")
        }

        // --- Decoder loop ------------------------------------------------------
        var curCharId = bosId
        var outputChars: [String] = []

        for _ in 0..<maxLemmaLen {
            let curArray = try MLMultiArray(shape: [1], dataType: .int32)
            curArray[[0] as [NSNumber]] = NSNumber(value: curCharId)

            let stepInput = try MLDictionaryFeatureProvider(dictionary: [
                "cur_char": curArray,
                "h": h,
                "c": c,
                "enc_out": encOut,
                "mask": maskArray,
            ])
            let stepOutput = try decoderStep.prediction(from: stepInput)

            guard let logits = stepOutput.featureValue(for: "logits")?.multiArrayValue,
                  let newH = stepOutput.featureValue(for: "new_h")?.multiArrayValue,
                  let newC = stepOutput.featureValue(for: "new_c")?.multiArrayValue else {
                throw LemmatizerError.modelLoadFailed("decoder step output missing expected fields see func neuralLemmatize")
            }

            let nextId = argmax(logits)
            if nextId == eosId { break }
            if nextId != padId && nextId != bosId && nextId != unkId {
                outputChars.append(charItos.indices.contains(nextId) ? charItos[nextId] : "")
            } else if nextId == unkId {
                // Model was unsure of this character; skip rather than
                // inserting a literal "<unk>" into the lemma.
            }

            curCharId = nextId
            h = newH
            c = newC
        }

        let lemma = outputChars.joined()
        return lemma.isEmpty ? form : lemma
//        return lemma.isEmpty ? form : "\(lemma)zz" //add zz to lemmas to test provenance
    }

    private func argmax(_ array: MLMultiArray) -> Int {
        let count = array.count
        var bestIdx = 0
        var bestVal = -Float.greatestFiniteMagnitude
        for i in 0..<count {
            let v = array[i].floatValue
            if v > bestVal {
                bestVal = v
                bestIdx = i
            }
        }
        return bestIdx
    }
}

