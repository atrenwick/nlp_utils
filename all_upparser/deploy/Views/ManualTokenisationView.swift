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
            
            HStack{
                Spacer()
                NavigationLink {
                    PrebuiltSentsView(newSentence: $newSentence, testSents: visibleSents)
                } label: {
                    Text("-> Prebuilt sents")
                }.buttonStyle(.borderedProminent)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                TextField("Add exciting sentence to tokenise", text: $newSentence).textFieldStyle(.roundedBorder)
                HStack{
                    Button {
                        let thisSentence: String
                        if newSentence.count == 0 {
                            thisSentence = testSentences[getsentNum]
                        } else {
                            thisSentence = newSentence
                        }
                        do {
                            let toksAsStrings = try TokenisationWorkflow.applyNaiveTokenisation(language: myConfig.parsingConfig.selectedLanguage, myString: thisSentence)
                            tempTokens = toksAsStrings.map {$0.asTempToken}
                        } catch {
                            PipelineError.IngestionError.retokenisationError
                            // what's this catch doing………
                        }
                    } label: {
                        Text("1. Tokenise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    
                    Spacer()
                    Button {
                        do {
                            builtSents.append( BuiltSentHolder(tempToks: tempTokens) )
                            print("Added 1 sent to builtSents")
                            tempTokens = []
                            newSentence = ""
                        }
                    } label: {
                        Text("2. Build")
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
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

//#Preview {
//    @Previewable @State var myConfig: TaggerConfig = TaggerConfig()
//    @Previewable @State var builtSents: [BuiltSentHolder] = []
//    @Previewable @State var tempTokens: [TempToken] = []
//    ManualTokenisationView(myConfig: $myConfig, builtSents: $builtSents, tempTokens: $tempTokens)
//}
//
struct AddSentButton: View {
    let addSysName: String
    let successSymbolSysName: String
    let action: () async throws -> Void

    @State private var succeeded = false
    @State private var bounceCount = 0

    var body: some View {
        Button {
            Task {
                do {
                    try await action()
                    flashSuccess()
                } catch {
                    // handle or surface the error
                }
            }
        } label: {
            Image(systemName: succeeded ? successSymbolSysName : addSysName)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: bounceCount)
                .foregroundStyle(.green)
                .fontWeight(.bold)

        }
        .sensoryFeedback(.success, trigger: bounceCount)
    }

    private func flashSuccess() {
        withAnimation(.spring(duration: 0.3)) { succeeded = true }
        bounceCount += 1
        
    }
}

struct PrebuiltSentsView: View {
    @Binding var newSentence: String
    @State var showSuccess: Bool = false
    let testSents: [String]
    
    var body: some View{
        Form{
            ForEach(testSents, id:\.self){testSentence in
                HStack{
                    Text(testSentence)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                        AddSentButton(addSysName: "plus.circle", successSymbolSysName: "checkmark.circle.fill"){
                            newSentence = testSentence
                        }

                    }
            }
        }
    }
    
}
#Preview {
    @Previewable @State var newSentence: String = "this is a sentence"
    @Previewable @State var testSents: [String] = ["Aujourd'hui, Paris est la capitale de la France parce qu'à l'époque, c'était la capitale.", "La capitale de l'Allemagne est Berlin, parce que Bonn n'était assez bonne pour tous", "Alors que Paris est une grande ville, elle est plus petite que Tokyo", "Li chevaliers combattent les dragons."]
    PrebuiltSentsView(newSentence: $newSentence, testSents: testSents)
}

