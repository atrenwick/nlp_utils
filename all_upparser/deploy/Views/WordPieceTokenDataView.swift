//
//  WordPieceTokenDataView.swift
//  Tagger
//
//  Created by Adam on 17/10/2026.
//

import SwiftUI
struct TestOutput{
    let tokenizer: WordPieceTokenizer
    let encoded: WordPieceEncodedSentence
}

struct WordPieceTokenDataView: View {
    
    @State var showWordPieces:Bool = false
    
    let words = "Colourless green ideas sleep furiously .".split(separator: " ")
    @State var testOutput: TestOutput?
    var body: some View {
                
        Button {
            do {
                testOutput = try testWordpieceTokenisation(
                    words: words.map {String($0)}
                )
            } catch {
                print("foobar")
                }
        } label: {
            Text("Tokenise")
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)

        
        if let testOutput {
            
            ForEach(Array(words.enumerated()), id:\.offset){_, word in
                HStack(alignment: .firstTextBaseline){
                    Text(word).bold()
                    Text(testOutput.tokenizer.subtokens(for: String(word)).joined(separator: ""))
                }
            }
        }
    }
    func testWordpieceTokenisation(words: [String]) throws -> TestOutput {
        
        
        do {
            let tokenizer: WordPieceTokenizer = try WordPieceTokenizer(
                // showWordPieces is always set to true, use view to toggle actually showing
                vocabURL: Bundle.main.url(forResource: "bert_tok_vocab", withExtension: "txt")!,
                configURL: Bundle.main.url(forResource: "bert_tok_config_settings", withExtension: "json")
            )
            guard !tokenizer.clsID.words.isEmpty else {
                print("WordPieceError.tokenizerTryError")
                throw WordPieceError.tokenizerTryError
            }
            
            let encoded = try tokenizer.encode(words: words, seqLen: 128, maxWords: 96)
            
            guard !encoded.inputIDs.isEmpty else {
                print("WordPieceError.wordPieceTokenizerError")
                throw WordPieceError.wordPieceTokenizerError
            }
            return TestOutput(tokenizer: tokenizer, encoded: encoded)
        } catch {
            print("other type of error")
            throw WordPieceError.other
        }
        
    }
}
//    func testMatchesPython() throws {
//        let tokenizer = try WordPieceTokenizer(
//            vocabURL: bundle.url(forResource: "vocab", withExtension: "txt")!,
//            configURL: bundle.url(forResource: "tokenizer_config", withExtension: "json"))
//        let failures = try tokenizer.checkAgainstGolden(
//            at: bundle.url(forResource: "tokenizer_golden", withExtension: "json")!)
//        XCTAssertEqual(failures, [])
//    }


#Preview {
    WordPieceTokenDataView()
}

//let encoded = try tokenizer.encode(words: words, seqLen: 128, maxWords: 96)
//let (ids, wordIndex) = try encoded.multiArrays()
//let output = try model.prediction(input_ids: ids, word_index: wordIndex)
//// read rows/columns 0 ..< encoded.wordCount + 1 of each output
////////////
///




