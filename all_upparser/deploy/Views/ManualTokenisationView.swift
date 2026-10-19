//
//  ManualTokenisationView.swift
//  Tagger
//
//  Created by Adam on 22/09/2026.
//

import SwiftUI

struct ManualTokenisationView: View {
    
    @Binding var myConfig: TaggerConfig
    @Binding var builtSents: [BuiltSentHolder]
    @Binding var tempTokens: [TempToken]

    @State var getsentNum: Int = 0
    @State private var newSentence: String = ""
    @State private var testSentences = ["Aujourd'hui, Paris est la capitale de la France parce qu'à l'époque, c'était la capitale.", "La capitale de l'Allemagne est Berlin, parce que Bonn n'était assez bonne pour tous", "Alors que Paris est une grande ville, elle est plus petite que Tokyo", "Li chevaliers combattent les dragons."]

    @FocusState var isFocused
    @State var alertMessage: String?
    
    private var visibleSents: [String] { Array(testSentences.prefix(5)) }
    
    var body: some View {
        NavigationStack{
            VStack(alignment: .leading, spacing: 16) {
                ForEach(visibleSents, id:\.self){testSentence in
                    Text("Input: \"\(testSentence)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                HStack{
                    TextField("Additional sentence", text: $newSentence).textFieldStyle(.roundedBorder)
                    Button("Add"){
                        if !newSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty{
                            testSentences.append(newSentence)
                            newSentence = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                //MARK: pickers for language, tokenisation method, view
                HStack{
                    Picker("Language", selection: $myConfig.parsingConfig.selectedLanguage) {
                        ForEach(Language.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(.blue)
                }
                HStack{
                    Button {
                        let thisSentence: String
                        if newSentence.count == 0 {
                            thisSentence = testSentences[getsentNum]
                        } else {
                            thisSentence = newSentence
                        }
                        do {
                            let toksAsStrings = try applyNaiveTokenisation(language: myConfig.parsingConfig.selectedLanguage, myString: thisSentence)
                            tempTokens = toksAsStrings.map {$0.asTempToken}
                        } catch {
                            ParseProcessingError.retokenisationError
                        }
                        
                    } label: {
                        Text("Tokenise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    Spacer()
                    Button {
                        if (0..<testSentences.count-1).contains(getsentNum - 1){
                            getsentNum -= 1
                        } else {
                            getsentNum = testSentences.count - 1
                        }
                    } label: {
                        HStack{
                            Text(String("-"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    Text(String(getsentNum))
                    Button {
                        if (0..<testSentences.count-1).contains(getsentNum + 1){
                            getsentNum += 1
                        } else {
                            getsentNum = 0
                        }
                    } label: {
                        HStack{
                            Text(String("+"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    
                    Spacer()
                    Button {
                        do {
                            builtSents.append( BuiltSentHolder(tempToks: tempTokens) )
                            print("Added 1 sent to builtSents")
                            tempTokens = []
                        }
                    } label: {
                        Text("Build")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                TokenisationEditView(toks: $tempTokens,  myConfig: $myConfig)
                Spacer()
            }
            .toolbar{
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        BuiltSentsViewer(myConfig: $myConfig, builtSents: $builtSents)
                    } label: {
                        Image(systemName: "textformat.characters.dottedunderline")
                            .overlay(alignment: .topTrailing) {
                                if builtSents.count > 0 {
                                    Text(String(builtSents.count))
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(Circle().fill(.red))
                                        .offset(x: 8, y: -8)
                                }
                            }
                    }
                }
            }
            .padding()
            .navigationTitle("Manual tokenisation")
        }
    }
}

#Preview {
    @Previewable @State var myConfig: TaggerConfig = TaggerConfig()
    @Previewable @State var builtSents: [BuiltSentHolder] = []
    @Previewable @State var tempTokens: [TempToken] = []
    ManualTokenisationView(myConfig: $myConfig, builtSents: $builtSents, tempTokens: $tempTokens)
}

