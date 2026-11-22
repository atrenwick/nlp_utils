//
//  TrainingPrepView.swift
//  Tagger
//
//  Created by Adam on 21/11/2026.
//

enum ElementToTrain: String, Identifiable, CaseIterable{
    var id: Self {self}
    case neurallem
    case tokenizer
    case taggerparser
    case rnnlemmatizer
    
    var tidy: String {
        switch self {
            case .neurallem: return "NeuralLemmatizer"
            case .tokenizer:  return "Tokenizer"
            case .taggerparser: return "Tagger-Parser"
            case .rnnlemmatizer: return "RNN-Lemmatizer"
        }
        }
    }
enum CommandType: String, Identifiable, CaseIterable{
    var id: Self {self}
    case train
    case convert
    case vocab
    
    var tidy: String {
        switch self{
            case .train: return "train"
            case .convert: return "convert"
            case .vocab: return "vocab"
        }
    }
}

import SwiftUI
import Foundation
struct TrainingPrepView: View{
    @State var selectedArchitecture: ModelArchitecture = .cnnBiLSTM
    @State var selectedTreebank: Language.Treebank = .frTB1
    @State var selectedLanguage: Language = .FR
    @State var devName: String = ""
    @State var trainName: String = ""
    @State var dataLocation: String = ""
    @State var outputFolder: String = ""
    

    @State var maxSubwords: Int = 512
    @State var maxWords: Int = 192
    @State var batchSize: Int = 64
    @State var cnnTokMaxSentLen: Int = 192

    @State var trainDataName: String = "trainDataName"
    @State var devDataName: String = "devDataName"
    @State var modelOutputName: String = "modelOutputName"
    @State var modelDir: String = "modelDir"
    @State var tokenizerDir: String = "tokenizerDir"
    @State var baseModel: String = "baseModel"
    @State var rnnTaggerDataFolder: String = "rnnTaggerDataFolder"
    @State var rnnLemDataFolder: String = "rnnLemDataFolder"
    @State var selectedTrainingElement: ElementToTrain = ElementToTrain.taggerparser
    @State var testtrainparams: TrainingParams = TrainingParams()
    @State var selectedCommandType: CommandType = CommandType.train
    
    
    var filteredCommandTypes: [CommandType] {
        switch selectedArchitecture {
            case .cnnBiLSTM: return [CommandType.train, CommandType.convert]
            case .rnn: return [CommandType.convert]
            default : return CommandType.allCases
        }
    }
    
   

    
    var body: some View{
        Form{
            Section{
                Picker("Architecture", selection: $selectedArchitecture){
                    ForEach(ModelArchitecture.allCases){architecture in
                        Text(architecture.displayName)
                    }
                }
                Picker("Element", selection: $selectedTrainingElement){
                    ForEach(selectedArchitecture.trainableElements){element in
                        Text(element.tidy)}
                }
                Picker("Type", selection: $selectedCommandType){

                    ForEach(filteredCommandTypes){ctype in
                        Text(ctype.tidy)}
                }
            }
            Section{
                
                if selectedCommandType == .train {
                    TextField("Train data name", text: $trainDataName)
                    TextField("Dev data name", text: $devDataName)
                    TextField("Data location", text: $dataLocation)
                    TextField("Model output name", text: $modelOutputName)
                    if [ModelArchitecture.camembert, ModelArchitecture.distilbert, ModelArchitecture.roberta].contains(selectedArchitecture){
                        TextField("base model", text: $baseModel)
                    }
                }
                if selectedCommandType == .convert{
                    TextField("Model dir", text: $modelDir)
                    TextField("Model output name", text: $modelOutputName)
                }
                if selectedCommandType == .vocab {
                    TextField("tokenizer dir", text: $tokenizerDir)
                }
                if selectedArchitecture == .rnn {
                    TextField("rnnTdatafolder", text: $rnnTaggerDataFolder)
                    TextField("rnnLdatafolder", text: $rnnLemDataFolder)
                }
                HStack{Text("Max words…")
                    TextField("Max words", value: $maxWords, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }
                HStack{Text("Max subwords…")
                    TextField("Max subwords", value: $maxSubwords, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }
                if selectedArchitecture == .cnnBiLSTM && selectedTrainingElement == .tokenizer{
                    HStack{Text("cnnTokMaxSentLength…")
                        TextField("Max subwords", value: $cnnTokMaxSentLen, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                   
                    HStack{Text("Batch size…")
                        TextField("Max subwords", value: $batchSize, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                    }
                }
            }
                
            }
            Section{

                
                Button{
                    print("hello")
                    testtrainparams = TrainingParams(
                        maxSubwords: maxSubwords,
                        maxWords: maxWords,
                        devName: devName,
                        trainName: trainName,
                        dataLocation: dataLocation,
                        outputFolder: outputFolder,
                        trainDataName: trainDataName,
                        devDataName: devDataName,
                        batchSize: batchSize,
                        modelOutputName: modelOutputName,
                        modelDir: modelDir,
                        cnnTokMaxSentLen: cnnTokMaxSentLen,
                        tokenizerDir: tokenizerDir,
                        baseModel: baseModel,
                        rnnTaggerDataFolder: rnnTaggerDataFolder,
                        rnnLemDataFolder: rnnLemDataFolder
                    )
                    
                } label : {
                    Text("print")
                }.buttonStyle(.borderedProminent)
            }
        }
    }
    
}
#Preview{
    TrainingPrepView()
}





@Observable
class TrainingCoordinator {
    var params = TrainingParams()
    var selectedArchitecture: ModelArchitecture = .cnnBiLSTM
    var selectedCommandType: CommandType = .train
    var selectedTrainingElement: ElementToTrain = .taggerparser
    var commandString: String {
        switch selectedTrainingElement {
            case .neurallem:
                switch selectedCommandType {
                    case .train:
                        if let dataLocation = params.dataLocation, let trainDataName = params.trainDataName, let devDataName = params.devDataName, let outputFolder = params.outputFolder, let batchSize = params.batchSize {
                            return "python -m lemmatizer.train --train \(dataLocation)/\(trainDataName).conllu --dev \(dataLocation)/\(devDataName).conllu --output \(outputFolder) --batch_size \(batchSize)"} else {
                                return "required  args missing"
                            }
                    case .convert:
                        if let modelDir = params.modelDir {
                            return "python -m lemmatizer.convert_lemmatizer --target_dir \(modelDir) --useBest"
                        } else { return "required args missing" }
                    case .vocab: return "error"
                }
            case .tokenizer:
                switch selectedArchitecture {
                    case .distilbert:
                        if let tokenizerDir = params.tokenizerDir {
                            return "python /tagger_parser/export_BERTtokenizer_files.py -- \(tokenizerDir))"
                        } else { return "required args missing" }
                    case .cnnBiLSTM:
                        switch selectedCommandType {
                            case .train:
                                if let dataLocation = params.dataLocation, let trainDataName = params.trainDataName, let devDataName = params.devDataName, let outputFolder = params.outputFolder {
                                    return "python -m tokenizer.train --train \(dataLocation)/\(trainDataName).conllu --dev \(dataLocation)/\(devDataName).conllu --output \(outputFolder) --batch_size 64"} else {
                                        return "required args missing"
                                    }
                            case .convert:
                                if let modelDir = params.modelDir, let modelOutputName = params.modelOutputName, let cnnTokMaxSentLen = params.cnnTokMaxSentLen {
                                    return "python -m tokenizer.convert --useBest --model_dir \(modelDir)) --output_name \(modelOutputName) --max_seq_len \(cnnTokMaxSentLen)"} else {
                                        return  "required args missing"
                                    }
                            case .vocab: return "error"
                        }
                    case .rnn: return "error"
                    case .camembert, .roberta:
                        if let tokenizerDir = params.tokenizerDir, let modelOutputName = params.modelOutputName {
                            return "python make_camembert_golden.py \(tokenizerDir) \(modelOutputName)_golden.json"
                        } else { return "required args missing" }
                }
            case .taggerparser:
                switch selectedCommandType {
                    case .train:
                        switch selectedArchitecture {
                            case .cnnBiLSTM:
                                if let dataLocation = params.dataLocation, let trainDataName = params.trainDataName, let devDataName = params.devDataName, let outputFolder = params.outputFolder {
                                    return  "python -m tagger_parser.train --train \(dataLocation)/\(trainDataName).conllu --dev \(dataLocation)/\(devDataName).conllu --output \(outputFolder)"} else {  return "required args missing" }
                            case .rnn: return "error"
                            case .camembert, .distilbert, .roberta:
                                if let dataLocation = params.dataLocation, let trainDataName = params.trainDataName, let devDataName = params.devDataName, let outputFolder = params.outputFolder, let baseModel = params.baseModel, let maxSubwords = params.maxSubwords {
                                    return "python -m tagger_parser.train_bert --train \(dataLocation)/\(trainDataName).conllu --dev \(dataLocation)/\(devDataName).conllu --output \(outputFolder) --base_model \(baseModel) --max_subwords \(maxSubwords)"
                                } else { return  "required args missing" }
                        }
                    case .convert:
                        switch selectedArchitecture {
                            case .distilbert:
                                if let modelDir =  params.modelDir, let modelOutputName = params.modelOutputName, let maxWords = params.maxWords, let maxSubwords = params.maxSubwords {
                                    return "python -m tagger_parser.convert_bert --useBest --model_dir \(modelDir) --output_name \(modelOutputName).mlpackage --max_words \(maxWords) --seq_len \(maxSubwords))"} else {
                                        return     "required args missing"
                                    }
                            case .cnnBiLSTM:
                                if let modelDir = params.modelDir, let modelOutputName = params.modelOutputName, let maxWords = params.maxWords, let maxSubwords = params.maxSubwords {
                                    return "python -m tagger_parser.convert --useBest --model_dir \(modelDir) --output_name \(modelOutputName).mlpackage --max_words \(maxWords) --seq_len \(maxSubwords))"
                                } else {
                                    return "required args missing"
                                }
                            case .rnn:
                                if let rnnTaggerDataFolder = params.rnnTaggerDataFolder, let outputFolder = params.outputFolder {
                                    return "python /Users/Adam/Downloads/allup/fromRNN/convert_rnntagger.py \(rnnTaggerDataFolder) --name \(outputFolder)"
                                } else { return "required args missing"}
                            case .camembert, .roberta:
                                if let modelDir = params.modelDir, let modelOutputName = params.modelOutputName, let maxSubwords = params.maxSubwords, let maxWords = params.maxWords{
                                    return "python -m tagger_parser.convert_camembertlikes --useBest --model_dir \(modelDir) --output_name \(modelOutputName).mlpackage --seq_len \(maxSubwords)) --max_words \(maxWords))"} else {
                                        return "required args missing"
                                    }
                        }
                    case .vocab: return "error"
                }
            // MARK: rrnn lemmatizer commands
            case .rnnlemmatizer:
                switch selectedCommandType {
                    case .train, .vocab:
                        return "error"
                    case .convert:
                        if let rnnLemDataFolder = params.rnnLemDataFolder, let outputFolder = params.outputFolder{
                            return  "python /Users/Adam/Downloads/allup/fromRNN/convert_nmt.py \(rnnLemDataFolder) --name \(outputFolder)"
                        } else { return "required args missing" }
                }
        }
    }
}
