//
//  ManualTokenisationView.swift
//  Tagger
//
//  Created by Adam on 22/09/2026.
//

import SwiftUI

struct ManualTokenisationView: View {
    
    @State var tempTokens: [TempToken] = []
    @State private var selectedRetokenisationType: RetokenisationType = .predict
    @State var getsentNum: Int = 0
    @State private var newSentence: String = ""
    @State private var testSentences = ["Aujourd'hui, Paris est la capitale de la France parce qu'à l'époque, c'était la capitale.", "La capitale de l'Allemagne est Berlin, parce que Bonn n'était assez bonne pour tous", "Alors que Paris est une grande ville, elle est plus petite que Tokyo", "Li chevaliers combattent les dragons."]
    
    @Binding var selectedLanguage: Language
    @Binding var builtSents: [BuiltSentHolder]
    @FocusState var isFocused
    
    private var visibleSents: [String] {
        Array(testSentences.prefix(5))
    }
    
    var body: some View {
        NavigationStack{
            VStack(alignment: .leading, spacing: 16) {
                Text("Manual entry")
                    .font(.title2)
                    .bold()
                
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
                    Picker("Language", selection: $selectedLanguage) {
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
                        tempTokens = applyNaiveTokenisation(language: selectedLanguage, myString: thisSentence
                        )
                    } label: {
                        Text("Tokenise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    Spacer()
                    Button {
                        if (0..<testSentences.count).contains(getsentNum - 1){
                            getsentNum -= 1
                        } else {
                            getsentNum = testSentences.count
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
                        if (0..<testSentences.count).contains(getsentNum + 1){
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
                        if let doneSent = makeHashableSentFromTestToks(
                            tempTokens: tempTokens) {
                            let currentSent = BuiltSentHolder(
                                hashableSent:doneSent,
                                showString: markupTokenisationInSent(hashableSent: doneSent)
                            )
                            builtSents.append(currentSent)
                            print("Added 1 sent to builtSents")
                        }
                        tempTokens = []
                        
                    } label: {
                        Text("Build")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                }
                Form{
                    ForEach($tempTokens, id:\.self) { token in
                        TextField("Token", text: token.form)
                            .textInputAutocapitalization(TextInputAutocapitalization.never)
                            .autocorrectionDisabled()
                            .focused($isFocused)
                            .submitLabel(.go)
                            .onSubmit {
                                isFocused = false
                            }
                    }
                }
                Spacer()
            }
            .toolbar{
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        BuiltSentsViewer(
                            builtSents: builtSents
                        )
                    } label: {
                        Image(systemName: "book.pages")
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
        }
    }
}

#Preview {
    @Previewable @State var selectedLanguage: Language = .FRM
    @Previewable @State var builtSents: [BuiltSentHolder] = []
    ManualTokenisationView(selectedLanguage: $selectedLanguage, builtSents: $builtSents)
}

