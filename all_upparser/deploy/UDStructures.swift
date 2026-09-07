//
//  conllTools.swift
//  moonshot
//
//  Created by Adam on 31/08/2026.
//

import Foundation


struct UDToken : Identifiable {
    var id = UUID()
    let tokid: Int
    let form: String
    let lemma: String
    let upos: String
    let xpos: String
    let feats: String
    let head: String
    let deprel: String
    let col8: String
    let col9: String
    /// Tab-separated, in CoNLL-U column order (ID FORM LEMMA UPOS XPOS FEATS HEAD DEPREL).
    var conlluLine: String {
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel].joined(separator: "\t")
    }
    
    var conllRaw: String{
        [String(tokid), form, lemma, upos, xpos, feats, head, deprel, "_","_"].joined(separator: "\t") + "\n"
    }
}


struct ConllSent : Identifiable {
    var id = UUID()
    let sentID: String
    let conllData: [UDToken]
    
    var sentIdAsMeta: String{
        return "# sent_id \(sentID)"
    }
    
    var conllSentRaw: String {
        var internalLineList: [String] = []
        internalLineList.append(sentIdAsMeta)
        for udToken in conllData{
            internalLineList.append(udToken.conllRaw)
        }
        return internalLineList.joined(separator: "\n")
    }
}



struct CoNLLDoc {
    var id = UUID()
    let sentences:[ConllSent]
    
    var docAsRaw: String{
        var internalList: [String] = []
        for sentence in sentences {
            internalList.append(sentence.conllSentRaw)
            internalList.append("\n")
        }
        
        return internalList.joined(separator: "\n")
    }
}
