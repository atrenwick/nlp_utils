//
//  TrainingPrepView.swift
//  Tagger
//
//  Created by Adam on 21/11/2026.
//

import SwiftUI
import Foundation


struct TrainingPrepView: View{
    @State private var coordinator = TrainingCoordinator()
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
    
    
    var body: some View{
        Form{
            Section{
                Picker("Architecture", selection: $coordinator.selectedArchitecture){
                    ForEach(ModelArchitecture.allCases){architecture in
                        Text(architecture.displayName)
                    }
                }
                Picker("Element", selection: $coordinator.selectedTrainingElement){
                    ForEach(filteredElements){element in
                        Text(element.tidy)}
                }
                Picker("Type", selection: $coordinator.selectedCommandType){
                    ForEach(filteredCommandTypes){ctype in
                        Text(ctype.tidy.localizedCapitalized)
                    }
                }
                TextField("Output folder", text: $coordinator.params.outputFolder.stringBinding())

            }
            Section{
                if coordinator.selectedCommandType == .train {
                    TextField("Train data name", text: $coordinator.params.trainDataName.stringBinding() )
                    TextField("Dev data name", text: $coordinator.params.devDataName.stringBinding())
                    TextField("Data location", text: $coordinator.params.dataLocation.stringBinding())
                    TextField("Model output name", text: $coordinator.params.modelOutputName.stringBinding())
                    if [ModelArchitecture.camembert, ModelArchitecture.distilbert, ModelArchitecture.roberta].contains(selectedArchitecture){
                        TextField("base model", text: $coordinator.params.baseModel.stringBinding())
                    }
                }
                if coordinator.selectedCommandType == .convert && coordinator.selectedArchitecture != .rnn && coordinator.selectedCommandType != .convert {
                    HStack{
                        Text("Max words…")
                        TextField("Max words", value: $coordinator.params.maxWords.intBinding(), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack{Text("Max subwords…")
                        TextField("Max subwords", value: $coordinator.params.maxSubwords.intBinding(), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        
                    }
                    if coordinator.selectedArchitecture != .rnn && coordinator.selectedCommandType != .convert {
                        TextField("Model dir", text: $coordinator.params.modelDir.stringBinding())}
                    if [.cnnBiLSTM, .rnn].contains(coordinator.selectedArchitecture) == false  {
                        TextField("Model output name", text: $coordinator.params.modelOutputName.stringBinding())
                    }
                }
                if coordinator.selectedCommandType == .vocab {
                    TextField("tokenizer dir", text: $coordinator.params.tokenizerDir.stringBinding())
                }
                if coordinator.selectedArchitecture == .rnn {
                    if coordinator.selectedTrainingElement == .taggerparser{
                        TextField("rnnTdatafolder", text: $coordinator.params.rnnTaggerDataFolder.stringBinding())}
                    if coordinator.selectedTrainingElement == .rnnlemmatizer{
                        TextField("rnnLdatafolder", text: $coordinator.params.rnnLemDataFolder.stringBinding())
                    }
                }
                if coordinator.selectedArchitecture == .cnnBiLSTM && coordinator.selectedTrainingElement == .neurallem {
                    HStack{
                        Text("cnnTokMaxSentLength…")
                        TextField("Max subwords", value: $coordinator.params.cnnTokMaxSentLen, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                    }
                    HStack{
                        Text("Batch size…")
                        TextField("Batch size", value: $coordinator.params.batchSize.intBinding(), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                    }
                }
            }
            Section{
                Button{
                    print("hello")
                    print("Arch = \(coordinator.selectedArchitecture.rawValue)")
                    print("Elem = \(coordinator.selectedTrainingElement.rawValue)")
                    print("type = \(coordinator.selectedCommandType.rawValue)")
                    print(coordinator.commandString)
                    
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

extension TrainingPrepView{
    var filteredCommandTypes: [CommandType] {
        switch coordinator.selectedArchitecture {
            case .rnn: return [CommandType.convert]
            case .cnnBiLSTM : return [CommandType.train, CommandType.convert]
          default: return [CommandType.train, CommandType.convert, CommandType.vocab]
        }
    }
    
    var filteredElements: [ElementToTrain]{
        switch coordinator.selectedArchitecture {
            case .rnn:
                return [ElementToTrain.rnnlemmatizer, ElementToTrain.taggerparser]
            case .cnnBiLSTM:
                return ElementToTrain.allCases.filter {$0.tidy != "RNN-Lemmatizer"}
            default : return [ElementToTrain.taggerparser, ElementToTrain.tokenizer]
        }
    }

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
                        //tested
                        if let dataLocation = params.dataLocation, let trainDataName = params.trainDataName, let devDataName = params.devDataName, let outputFolder = params.outputFolder, let batchSize = params.batchSize {
                            return "python -m lemmatizer.train --train \(dataLocation)/\(trainDataName).conllu --dev \(dataLocation)/\(devDataName).conllu --output \(outputFolder) --batch_size \(batchSize)"} else {
                                return "error1"
                            }
                        //tested, has
                    case .convert:
                        if let modelDir = params.modelDir {
                            return "python -m lemmatizer.convert_lemmatizer --target_dir \(modelDir) --useBest"
                        } else { return "error2" }
                    case .vocab: return "error3"
                }
            case .tokenizer:
                switch selectedArchitecture {
                    case .distilbert:
                        if let tokenizerDir = params.tokenizerDir {
                            return "python /tagger_parser/export_BERTtokenizer_files.py -- \(tokenizerDir))"
                        } else { return "required args missing error4" }
                    case .cnnBiLSTM:
                        switch selectedCommandType {
                            case .train:
                                if let dataLocation = params.dataLocation, let trainDataName = params.trainDataName, let devDataName = params.devDataName, let outputFolder = params.outputFolder {
                                    return "python -m tokenizer.train --train \(dataLocation)/\(trainDataName).conllu --dev \(dataLocation)/\(devDataName).conllu --output \(outputFolder) --batch_size 64"} else {
                                        return "required args missing: error5"
                                    }
                            case .convert:
                                if let modelDir = params.modelDir, let modelOutputName = params.modelOutputName, let cnnTokMaxSentLen = params.cnnTokMaxSentLen {
                                    return "python -m tokenizer.convert --useBest --model_dir \(modelDir) --output_name \(modelOutputName) --max_seq_len \(cnnTokMaxSentLen)"} else {
                                        return  "required args missing: eror6"
                                    }
                            case .vocab: return "error"
                        }
                    case .rnn: return "error"
                    case .camembert, .roberta:
                        if let tokenizerDir = params.tokenizerDir, let modelOutputName = params.modelOutputName {
                            return "python make_camembert_golden.py \(tokenizerDir) \(modelOutputName)_golden.json"
                        } else { return "required args missing : error7" }
                    case .camembertav2:
                        if let tokenizerDir = params.tokenizerDir, let modelOutputName = params.modelOutputName {
                            return "python make_camembertav2_golden.py \(tokenizerDir) \(modelOutputName)_golden.json"
                        } else { return "required args missing : error7b" }
                }
            case .taggerparser:
                switch selectedCommandType {
                    case .train:
                        switch selectedArchitecture {
                            case .cnnBiLSTM:
                                if let dataLocation = params.dataLocation, let trainDataName = params.trainDataName, let devDataName = params.devDataName, let outputFolder = params.outputFolder {
                                    return  "python -m tagger_parser.train --train \(dataLocation)/\(trainDataName).conllu --dev \(dataLocation)/\(devDataName).conllu --output \(outputFolder)"} else {  return "required args missing error 8" }
                            case .rnn: return "error: 9"
                            case .camembert, .camembertav2, .distilbert, .roberta:
                                if let dataLocation = params.dataLocation, let trainDataName = params.trainDataName, let devDataName = params.devDataName, let outputFolder = params.outputFolder, let baseModel = params.baseModel, let maxSubwords = params.maxSubwords {
                                    return "python -m tagger_parser.train_bert --train \(dataLocation)/\(trainDataName).conllu --dev \(dataLocation)/\(devDataName).conllu --output \(outputFolder) --base_model \(baseModel) --max_subwords \(maxSubwords)"
                                } else { return  "required args missing: error10" }
                        }
                    case .convert:
                        switch selectedArchitecture {
                            case .distilbert:
                                if let modelDir =  params.modelDir, let modelOutputName = params.modelOutputName, let maxWords = params.maxWords, let maxSubwords = params.maxSubwords {
                                    return "python -m tagger_parser.convert_bert --useBest --model_dir \(modelDir) --output_name \(modelOutputName).mlpackage --max_words \(maxWords) --seq_len \(maxSubwords)"} else {
                                        return     "required args missing :: error11"
                                    }
                            case .cnnBiLSTM:

                                if let modelDir = params.modelDir, let modelOutputName = params.modelOutputName, let maxWords = params.maxWords, let maxSubwords = params.maxSubwords {
                                    return "python -m tagger_parser.convert --useBest --model_dir \(modelDir) --output_name \(modelOutputName).mlpackage --max_words \(maxWords) --seq_len \(maxSubwords)"
                                } else {
                                    return "required args missing error12"
                                }
                            case .rnn:
                                if let rnnTaggerDataFolder = params.rnnTaggerDataFolder, let outputFolder = params.outputFolder {
                                    return "python /Users/Adam/Downloads/allup/fromRNN/convert_rnntagger.py \(rnnTaggerDataFolder) --name \(outputFolder)"
                                } else { return "required args missing error13"}
                            case .camembert, .roberta:
                                if let modelDir = params.modelDir, let modelOutputName = params.modelOutputName, let maxSubwords = params.maxSubwords, let maxWords = params.maxWords{
                                    return "python -m tagger_parser.convert_camembertlikes --useBest --model_dir \(modelDir) --output_name \(modelOutputName).mlpackage --seq_len \(maxSubwords) --max_words \(maxWords)"} else {
                                        return "required args missing error14"
                                    }
                            case .camembertav2:
                                if let modelDir = params.modelDir, let modelOutputName = params.modelOutputName, let maxSubwords = params.maxSubwords, let maxWords = params.maxWords{
                                    return "python -m tagger_parser.convert_camembertav2 --useBest --model_dir \(modelDir) --output_name \(modelOutputName).mlpackage --seq_len \(maxSubwords) --max_words \(maxWords)"} else {
                                        return "required args missing error14b"
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
                        } else { return "required args missing error 15" }
                }
        }
    }
}

@Observable
class TrainingParams {
    var maxSubwords: Int?
    var maxWords: Int?
    var devName: String?
    var trainName: String?
    var dataLocation: String?
    var outputFolder: String?
    var trainDataName: String?
    var devDataName: String?
    var batchSize: Int?
    var modelOutputName: String?
    var modelDir: String?
    var cnnTokMaxSentLen: Int?
    var tokenizerDir: String?
    var baseModel: String?
    var rnnTaggerDataFolder: String?
    var rnnLemDataFolder: String?
    
    init(
        maxSubwords: Int? = nil,
        maxWords: Int? = 512,//nil,
        devName: String? = nil,
        trainName: String? = nil,
        dataLocation: String? = nil,
        outputFolder: String? = nil,
        trainDataName: String? = nil,
        devDataName: String? = nil,
        batchSize: Int? = nil,
        modelOutputName: String? = nil,
        modelDir: String? = nil,
        cnnTokMaxSentLen: Int? = nil,
        tokenizerDir: String? = nil,
        baseModel: String? = nil,
        rnnTaggerDataFolder: String? = nil,
        rnnLemDataFolder: String? = nil,
    ) {
        self.maxSubwords = maxSubwords
        self.maxWords = maxWords
        self.devName = devName
        self.trainName = trainName
        self.dataLocation = dataLocation
        self.outputFolder = outputFolder
        self.trainDataName = trainDataName
        self.devDataName = devDataName
        self.batchSize = batchSize
        self.modelOutputName = modelOutputName
        self.modelDir = modelDir
        self.cnnTokMaxSentLen = cnnTokMaxSentLen
        self.tokenizerDir = tokenizerDir
        self.baseModel = baseModel
        self.rnnTaggerDataFolder = rnnTaggerDataFolder
        self.rnnLemDataFolder = rnnLemDataFolder
    }
}


