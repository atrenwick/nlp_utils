//
//  SourceContainerClass.swift
//  Tagger
//
//  Created by Adam on 10/09/2026.
//

import Foundation


@Observable
class SourceFileContainerModel {
    // to make a shared, mutable state container across multiple views -->> use Class
    var localSandboxFileURL: URL?
    
    var selectedFileName: String {
        localSandboxFileURL?.lastPathComponent ?? "No file selected"
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
            print("have sent :: tokens == ")
            results.append(HashableSentence(id: id, tokens: currentTokens))
            insideS = false

        default:
            break
        }
    }
}
