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
    var body: some View{
        Text(item.tokID)
        Text(item.form)
        switch selectedGridOption {
            case .pos:
                Text(item.pos1)
                Text(item.pos2)
            case .lemma:
                Text(item.lemma1)
                Text(item.lemma2)
            case .feats:
                Text(item.feats1)
                Text(item.feats2)
            case .head:
                Text(item.head1)
                Text(item.head2)
            case .deprel:
                Text(item.deprel1)
                Text(item.deprel2)
        }
        
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
