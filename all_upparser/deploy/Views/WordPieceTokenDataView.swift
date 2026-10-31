//
//  WordPieceTokenDataView.swift
//  Tagger
//
//  Created by Adam on 17/10/2026.
//

import SwiftUI
//struct TestOutput{
//    let tokenizer: WordPieceTokenizer
//    let encoded: WordPieceEncodedSentence
//}


//struct WordPieceTokenDataView: View {
//    
//    @State var showWordPieces:Bool = false
//    
//    let words = "Colourless green ideas sleep furiously .".split(separator: " ")
//    @State var testOutput: [String] = []
//    let languageCode: String = "FR"
//    let treebank: String = "gsd"
//    var body: some View {
//                
//        Button {
//            do {
//                testOutput = try testWordpieceTokenisation(
//                    words: words.map {String($0)}
//                )
//            } catch {
//                print("foobar")
//                }
//        } label: {
//            Text("Tokenise")
//        }
//        .buttonStyle(.borderedProminent)
//        .tint(.indigo)
//
//        
//         
//            Form{
//                ForEach(testOutput.enumerated(), id:\.offset){(_, outputitem) in
//                    Text(outputitem)
//                }
////            ForEach(Array(words.enumerated()), id:\.offset){_, word in
////                HStack(alignment: .firstTextBaseline){
////                    Text(word).bold()
////                    Text(testOutput.tokenizer.subtokens(for: String(word)).joined(separator: ""))
////                }
////            }
//        }
//    }
////    func testWordpieceTokenisation(words: [String]) throws -> [String] {
////        
////        
////        do {
////            let wordPieceTokenizer: WordPieceTokenizer = try WordPieceTokenizer.fromBundle(languageCode: languageCode, treebank: treebank)
////
////
////            guard !wordPieceTokenizer.clsID.words.isEmpty else {
////                print("TokPieceError.tokenizerTryError")
////                throw TokPieceError.tokenizerTryError
////            }
////            
////            let encoded = try wordPieceTokenizer.encode(words: words, seqLen: 128, maxWords: 96)
////            print(encoded.wordCount)
////            guard !encoded.inputIDs.isEmpty else {
////                print("TokPieceError.wordPieceTokenizerError")
////                throw TokPieceError.wordPieceTokenizerError
////            }
//////            return TestOutput(tokenizer: wordPieceTokenizer, encoded: encoded)
////            let failures = try wordPieceTokenizer.checkAgainstGolden(fileNameChunk: "FR_distilbert_tok_gold_gsd")
////            
////            print(failures)
////            return failures
////
////        } catch {
////            print("other type of error")
////            throw TokPieceError.other
////        }
////        
////    }
//}
//    func testMatchesPython() throws {
//        let tokenizer = try WordPieceTokenizer(
//            vocabURL: bundle.url(forResource: "vocab", withExtension: "txt")!,
//            configURL: bundle.url(forResource: "tokenizer_config", withExtension: "json"))
//        let failures = try tokenizer.checkAgainstGolden(
//            at: bundle.url(forResource: "tokenizer_golden", withExtension: "json")!)
//        XCTAssertEqual(failures, [])
//    }

//
//#Preview {
//    WordPieceTokenDataView()
//}

//let encoded = try tokenizer.encode(words: words, seqLen: 128, maxWords: 96)
//let (ids, wordIndex) = try encoded.multiArrays()
//let output = try model.prediction(input_ids: ids, word_index: wordIndex)
//// read rows/columns 0 ..< encoded.wordCount + 1 of each output
////////////
///





//struct BERTPipeTestView: View{
//    @State var outputString: String = ""
//    let languageCode = "FR"
//    let treebank = "gsd"
//    let myConfig: TaggerConfig
//    @State private var pipeline: BERTlikePipeline?
//    @State var alertMessage: String?
//    var body: some View{
//        
//        HStack{
//            Button {
//                outputString = "pressed"//testInstBertPipe(languageCode: languageCode, treebank: treebank)
//            } label: {
//                Text("Test load")
//            }
//            .tint(.orange)
//            .buttonStyle(.borderedProminent)
//            .task(id: languageCode) {
//                pipeline = nil
//                do {
//                    pipeline = try await BERTlikePipeline.load(myConfig: myConfig, version: 2)
//                    alertMessage = "Success !"
//                } catch {
//                    alertMessage = error.localizedDescription
//                }
//            }
//            
//            Button {
//                outputString = "reset"
//            } label: {
//                Text("reset")
//            }
//            .tint(.blue)
//            .buttonStyle(.borderedProminent)
//        }
//        Text(outputString)
//    }
//    
//
//func testInstBertPipe(languageCode: String, treebank: String) -> String {
//        // test instantiation of pipeline class based on params chosen
//        var outputString: String = ""
//        
//        Task{
//            do {
//                let _ = try BERTlikePipeline(myConfig: myConfig, version: 2)
//                await MainActor.run {
//                    outputString = "Success"
//                    print(outputString)
//                }
//            } catch {
//                await MainActor.run {
//                    outputString = "Fail : \(error.localizedDescription)"
//                    print(outputString)
//                }
//            }
//        }
//        return outputString
////}
////}
//#Preview {
//    @Previewable @State var myConfig: TaggerConfig = TaggerConfig()
//    BERTPipeTestView(myConfig: myConfig)
//}
////
////
//
