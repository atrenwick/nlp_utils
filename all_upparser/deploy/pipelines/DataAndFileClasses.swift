//
//  DataAndFileClasses.swift
//  Tagger
//
//  Created by Adam on 10/09/2026.
//  Classes used in decoding, reading, parsing, saving data

import Foundation

//MARK: 1 class for interacting with sandbox
@Observable
class SourceFileContainerModel {
    // to make a shared, mutable state container across multiple views -->> use Class
    var localSandboxFileURL: URL?
    
    var selectedFileName: String {
        localSandboxFileURL?.lastPathComponent ?? "No file selected"
    }
}

//MARK: 2 : Classes: for loading, decoding, parsing
//define the vocab class
final class Vocab {
    let itos: [String]
    let stoi: [String: Int]
    let pad: String
    let unk: String
    
    //   //init method for the vocab class
    init(data: VocabData) {
        itos = data.itos
        pad = data.pad
        unk = data.unk
        var map = [String: Int](minimumCapacity: data.itos.count)
        for (i, s) in data.itos.enumerated() { map[s] = i }
        stoi = map
    }

    var unkId: Int { stoi[unk] ?? 1 }

    func encode(_ token: String) -> Int {
        stoi[token] ?? unkId
    }

    func decode(_ id: Int) -> String {
        (id >= 0 && id < itos.count) ? itos[id] : unk
    }

    //func to get path to file, load, decode and return decoded data based on name of json file
    static func load(named name: String, bundle: Bundle = .main) throws -> Vocab {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw PipelineError.GenericError.missingResource("\(name).json")
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(VocabData.self, from: data)
        return Vocab(data: decoded)
    }
}

//NOTE for parser, delegate, class :::  `parser` functions below aren't strictly overloaded : functs can have same basename IF full function signatures are different :: each function  corresponds to a distinct lifecycle event that XMLParser needs to report to its delegate — names are required too - parser is the name of one of the 'behind the scenes' functions in the XMLParser I want the delegate to call

//XML parsing looking for s elements ->> used for XML-CONLL parsing:: get s block, text == s.text
class SParser: NSObject, XMLParserDelegate {
    var results: [XMLConllElement] = []
    private var currentID: String?
    private var currentText: String = ""
    private var insideS = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "s" {
            insideS = true
            currentID = attributes["id"]
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideS { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "s", let id = currentID {
            let fullBlob = "# sent_id = \(id)\n" + currentText
            results.append(XMLConllElement(id: id, blob: fullBlob))
            insideS = false
        }
    }
}


class SWParser: NSObject, XMLParserDelegate {
    var results: [HashableSentence] = []

    private var currentSID: String?
    private var currentTokens: [String] = []
    private var insideS = false
    private var insideW = false
    private var currentTokText: String = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch elementName {
        case "s":
            insideS = true
            currentSID = attributes["id"]
            currentTokens = []

        case "w":
            guard insideS else { return }
            insideW = true
            currentTokText = ""   // w's own id (attributes["id"]) is available here if needed later

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideW else { return }
        currentTokText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "w":
            guard insideS, insideW else { return }
            currentTokens.append(currentTokText)
            insideW = false

        case "s":
            guard let id = currentSID else { return }
            print("have sent :: tokens == \(currentTokens.count)")
            results.append(HashableSentence(id: id, tokens: currentTokens, conllMetas: []))
            insideS = false

        default:
            break
        }
    }
}
