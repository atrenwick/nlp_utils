//
//  RunErrorSummaryView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI

struct RunErrorSummaryView: View{
    let myConfig: TaggerConfig
    let toksIn: Int
    
    var body: some View{
        Form{
            Text("Sents: \(errorCases.count) errors in \(totalSents) sents -> \(sentCoverage) % coverage")
            Text("Toks: \(toksIn) in -> \(totalOutputToks) out :: \(tokCoverage) %")
            ForEach(errorCases.enumerated(), id: \.offset){(num,item) in
                VStack{
                    Text(makeSentStartString(num: num, item: item))
                    HStack{
                        Text(item.errorType.rawValue)
                        Text("Toks: \(item.tokCount) :: Subtoks: \(item.subtokCount)")
                    }
                }
            }
        }
    }
}

extension RunErrorSummaryView {
    var errorCases: [OutputError] { myConfig.outputData.outErrors}
    var totalSents: Int {  errorCases.count + myConfig.outputData.outSents.count }
    var totalOutputToks: Int { myConfig.outputData.outSents.reduce(0) {$0 + $1.tokCount}  }
    
    var sentCoverage: String {
        let intermed = 1 - (Double(errorCases.count) / Double(totalSents))
        return String(format: "%.2f", (intermed * 100))
    }
    var tokCoverage: String {
        if toksIn == 0 || totalOutputToks == 0 {
            return " ??? "
        } else {
            return String(
                format: "%.2f", ( Double(totalOutputToks) / Double(toksIn) * 100 )
            )
        }
    }
    func makeSentStartString(num: Int, item: OutputError)-> String{
        let numStr = String(num+1)
        let tokChunk = item.sentence.tokens.prefix(5).joined(separator: " ")
        return "\(numStr): \(tokChunk)"
    }

}
