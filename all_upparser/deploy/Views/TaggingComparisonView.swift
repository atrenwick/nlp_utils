//
//  ComparisonGridOption.swift
//  Tagger
//
//  Created by Adam on 17/11/2026.
//
import Foundation
import SwiftUI

struct TaggingComparisonView: View{
    @Environment(AppModel.self) private var model
    @State var resultSet: [ComparisonElement] = []
    @State var selectedGridOption: ComparisonGridOption = .pos
    let runPair: [RunOutput]

    var body: some View{
        Picker("Show what", selection: $selectedGridOption){
            ForEach(ComparisonGridOption.allCases){option in
                Text(option.rawValue)
            }
        }.pickerStyle(.segmented)
        
        if runPair.count != 2 {
            Text("Runs selected.count  != 2")
        } else {
            ScrollView{
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        ComparisonGridRowHead(selectedGridOption: selectedGridOption)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                    ForEach(processRunPair(run1: runPair[0], run2: runPair[1])) { item in
                        GridRow {
                            ComparisonGridRowBody(selectedGridOption: selectedGridOption, item: item)
                        }
                    }
                }
            }
        }
    }
    
    func processRunPair(run1: RunOutput, run2: RunOutput)-> [ComparisonElement] {
        var internalResults: [ComparisonElement] = []
                for (sent1, sent2) in zip(run1.runData.sents, run2.runData.sents){
                    for (token1, token2) in zip(sent1.conllData, sent2.conllData){
                        internalResults.append(
                            ComparisonElement(
                                uuid: token1.unwrappedUUID,
                                tokID: String(token1.tokid),
                                form: token1.form,
                                pos1: token1.upos == "_" ? token1.xpos : token1.upos,
                                pos2: token2.upos == "_" ? token2.xpos : token2.upos,
                                lemma1: token1.lemma,
                                lemma2: token2.lemma,
                                feats1: token1.feats,
                                feats2: token2.feats,
                                deprel1: token1.deprel,
                                deprel2: token2.deprel,
                                head1: token1.head,
                                head2: token2.head,
                            )
                        )
                    }
                }
        return internalResults
    }
}

struct ComparisonGridRowBody: View{
    let selectedGridOption: ComparisonGridOption
    let item: ComparisonElement
    
    var annotations: [String] {
        switch selectedGridOption {
            case .pos: return [item.pos1, item.pos2]
            case .lemma: return [item.lemma1, item.lemma2]
            case .feats: return [item.feats1, item.feats2]
            case .head: return [item.head1, item.head2]
            case .deprel: return [item.deprel1, item.deprel2]
        }
    }
    
    var body: some View{
        Text(item.tokID)
        Text(item.form)
        Group{
            Text(annotations[0])
            Text(annotations[1])
        }
        .foregroundStyle(annotations[0] == annotations[1] ? .green : .orange )
    }
}


struct ComparisonGridRowHead: View{
    let selectedGridOption: ComparisonGridOption
    var body: some View{
        Text("TokID").bold()
        Text("Form").bold()
        switch selectedGridOption {
            case .pos:
                Text("POS 1").bold()
                Text("POS 2").bold()
            case .lemma:
                Text("LEM 1").bold()
                Text("LEM 2").bold()
            case .feats:
                Text("FEAT 1").bold()
                Text("FEAT 2").bold()
            case .head:
                Text("HEAD 1").bold()
                Text("HEAD 2").bold()
            case .deprel:
                Text("DEP 1").bold()
                Text("DEP 2").bold()
        }
        
    }
}

/// prefer pure dict to join on UUID for toks ->> dict1 of token level info, dict 2 of sent-token mapping
func consolidateRunsToXML(runs: [RunOutput]){
    var consolidatedSents: [ConsolidatedSentence] = []
    var consolidatedTokens: [ConsolidatedToken] = []
    for (runNum, run) in runs.enumerated(){
        // process sent
        var currentSentID: String = ""
        for sent in run.runData.sents{
            if runNum == 0 {
                currentSentID = sent.sentID
                //do this to start sent
            }
            // process token
            for token in sent.conllData{
                var tokid: Int = 0
                var form: String = ""
                var unwrappedUUID: String = ""
                var posData: [ConsolidatedAnnotationData] = []
                var lemmaData: [ConsolidatedAnnotationData] = []
                var featsData: [ConsolidatedAnnotationData] = []
                var headData: [ConsolidatedAnnotationData] = []
                var deprelData: [ConsolidatedAnnotationData] = []
                if runNum == 0 {
                    // do this to add token
                    let key = "\(run.runMetas.safeHeaderAttribs.modelArchitecture)_\(run.runMetas.treebank)"
                    tokid = token.tokid
                    form = token.form
                    unwrappedUUID = token.preservedUUID ?? "_"
                    posData.append(ConsolidatedAnnotationData(source: "\(key)", value: token.upos))
                    lemmaData.append(ConsolidatedAnnotationData(source: "\(key)", value: token.upos))
                    featsData.append(ConsolidatedAnnotationData(source: "\(key)", value: token.upos))
                    headData.append(ConsolidatedAnnotationData(source: "\(key)", value: token.upos))
                    deprelData.append(ConsolidatedAnnotationData(source: "\(key)", value: token.upos))
                } else {
                    let key = "\(run.runMetas.safeHeaderAttribs.modelArchitecture)_\(run.runMetas.treebank)"
                    posData.append(ConsolidatedAnnotationData(source: "\(key)", value: token.upos))
                    lemmaData.append(ConsolidatedAnnotationData(source: "\(key)", value: token.upos))
                    featsData.append(ConsolidatedAnnotationData(source: "\(key)", value: token.upos))
                    headData.append(ConsolidatedAnnotationData(source: "\(key)", value: token.upos))
                    deprelData.append(ConsolidatedAnnotationData(source: "\(key)", value: token.upos))
                }
                consolidatedTokens.append(
                    ConsolidatedToken(
                    tokid: tokid,
                    tokUUID: unwrappedUUID,
                    form: form,
                    posData: posData,
                    lemmaData: lemmaData,
                    featsData: featsData,
                    headData: headData,
                    deprelData: deprelData
                )
                    )
            }
            
            
        }
        consolidatedSents.append(
            ConsolidatedSentence(
                sentID: currentSentID,
                consolidatedData: consolidatedTokens)
        )
        consolidatedTokens = []
        
        
        
        
        
    }
    
}
struct ConsolidatedAnnotationData: Identifiable, Codable{
    var id = UUID()
    let source: String
    let value: String
}

struct ConsolidatedToken: Identifiable, Codable{
    var id = UUID()
    let tokid: Int
    let tokUUID: String
    let form: String
    let posData: [ConsolidatedAnnotationData]
    let lemmaData: [ConsolidatedAnnotationData]
    let featsData: [ConsolidatedAnnotationData]
    let headData: [ConsolidatedAnnotationData]
    let deprelData: [ConsolidatedAnnotationData]
}

struct ConsolidatedSentence: Identifiable, Codable{
    var id = UUID()
    let sentID: String
    let consolidatedData: [ConsolidatedToken]
    
}
