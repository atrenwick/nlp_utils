//
//  ManualTokenisationView.swift
//  Tagger
//
//  Created by Adam on 22/09/2026.
//

import SwiftUI

struct ManualTokenisationView: View {
    
    @Binding var tempTokens: [TempToken]
    @Binding var selectedRetokenisationType: RetokenisationType
    @State var getsentNum: Int = 0
    @State private var newSentence: String = ""
    @State private var testSentences = ["Aujourd'hui, Paris est la capitale de la France parce qu'à l'époque, c'était la capitale.", "La capitale de l'Allemagne est Berlin, parce que Bonn n'était assez bonne pour tous", "Alors que Paris est une grande ville, elle est plus petite que Tokyo", "Li chevaliers combattent les dragons."]
    
    @Binding var selectedLanguage: Language
    @Binding var builtSents: [BuiltSentHolder]
    @Binding var insertNewTokPosition: InsertPosition
    @FocusState var isFocused
    @State var alertMessage: String?
    
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
                        let toksAsStrings = applyNaiveTokenisation(language: selectedLanguage, myString: thisSentence)
                       tempTokens = toksAsStrings.map {$0.asTempToken}
                        
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
                            builtSents.append(
                                BuiltSentHolder(tempToks: tempTokens)
                            )
                            print("Added 1 sent to builtSents")
                            tempTokens = []
                        }
                    } label: {
                        Text("Build")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                }
                TokenisationEditView(toks: $tempTokens, insertNewTokPosition: $insertNewTokPosition)
                Spacer()
            }
            .toolbar{
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        BuiltSentsViewer(
                            builtSents: $builtSents,
                            insertNewTokPosition: $insertNewTokPosition
                        )
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
        }
    }
}

#Preview {
    @Previewable @State var selectedLanguage: Language = .FRM
    @Previewable @State var builtSents: [BuiltSentHolder] = []
    @Previewable @State var insertNewTokPosition: InsertPosition = .after
    @Previewable @State var tempTokens: [TempToken] = []
    @Previewable @State var selectedRetokenisationType: RetokenisationType = .predict
    
    ManualTokenisationView(
        tempTokens: $tempTokens,
        selectedRetokenisationType: $selectedRetokenisationType,
        selectedLanguage: $selectedLanguage,
        builtSents: $builtSents,
        insertNewTokPosition: $insertNewTokPosition
        
    )
}

func removeFromBuiltSentArray(from array: inout [BuiltSentHolder], at offsets: IndexSet) {
    // 1. Guard against empty inputs
    guard !offsets.isEmpty else { return }
    
    // 2. Filter the offsets to ensure they are actually within the current bounds.
    let validOffsets = IndexSet(offsets.filter { $0 < array.count })
    // If no offsets are valid (e.g., the user swiped on a deleted cell), just bail.
    guard !validOffsets.isEmpty else { return }
    
    // 3. Perform the removal
    // We use the validOffsets to ensure we only touch existing indices.
    array.remove(atOffsets: validOffsets)
}
