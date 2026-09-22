//
//  ManualTokenisationView.swift
//  Tagger
//
//  Created by Adam on 22/09/2026.
//

import SwiftUI

struct ManualTokenisationView: View {
    
    @State private var language: Language = .FR
    @State private var currentTokenisationType: TokenisationMethod = .conll
    @FocusState var isFocused
    @State var testTokens: [TestToken] = []
    @Binding var builtSents: [HashableSentence]
 
    
    //2 hardcoded sents for testing
    //MARK: data
//

    @State private var testSentences = ["Aujourd'hui, Paris est la capitale de la France parce qu'à l'époque, c'était la capitale.", "La capitale de l'Allemagne est Berlin, mais avant, c'était Bonn mais on trouvait que c'était pas bon.", "Paris est une grande ville française"]
    @State private var newSentence: String = ""

    private var visibleSents: [String] {
        Array(testSentences.prefix(5))
    }

    
    var body: some View {
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
                Picker("Language", selection: $language) {
                    ForEach(Language.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.blue)
                Picker("Tokenisation", selection: $currentTokenisationType) {
                    ForEach(TokenisationMethod.allCases) { mode in
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
                        thisSentence = testSentences[0]
                    } else {
                        thisSentence = newSentence
                    }
                    testTokens = applyNaiveTokenisation(language: language, myString: thisSentence
                    )
                } label: {
                Text("Tokenise")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)

                Spacer()
                Button {
                    if let doneSent = makeHashableSentFromTestToks(testTokens: testTokens)
                        {
                            builtSents.append(doneSent)
                        print("Added 1 sent to builtSents")
                        }
                    testTokens = []
                    
                } label: {
                Text("done")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

            }
            
            Form{
                ForEach($testTokens, id:\.self) { token in
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
        .padding()
    }
    func applyNaiveTokenisation(language: Language, myString: String)-> [TestToken]{
        
        let input: String = myString
        var testTokens: [TestToken] = []
        var step1: [Substring] = []
        if language == .FR {
            
            let replacements: [String: String] = [
                "jourd'hui": "jourdhui",
                "rud'homm": "rudhomm",
                "'":"' "
            ]
            let unreplacements: [String: String] = [
                "jourdhui": "jourd'hui",
                "rudhomm": "rud'homm"
            ]

            let unreplacePattern = unreplacements.keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            let regexUnreplace = try! Regex(unreplacePattern)

            let literalPattern = replacements.keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            let fullPattern = "(\(literalPattern))|([.?!]$)|([,;:])"
            let regex = try! Regex(fullPattern)

            
            let frResult = myString.replacing(regex) { match in
                let matchedText = String(match.0)
                if matchedText == "." && match.0 == myString.suffix(1) {
                    return " ."
                }
                if let replacement = replacements[matchedText] {
                    return replacement
                }
                // must be punctuation needing a leading space
                return " " + matchedText
            }
            var preSplit = frResult.replacingOccurrences(of: "  ", with: " ")
            
            preSplit = preSplit.replacing(regexUnreplace) { match in
                unreplacements[String(match.0)] ?? String(match.0)
            }
            step1 = preSplit.split(whereSeparator: { $0 == " " })
        } // end FR
        
        if language == .EN {
            step1 = input.split(whereSeparator: { $0 == " "})
        }

        for (num, item) in step1.enumerated() {
            testTokens.append(
                TestToken(id: num, form: String(item))
                                )
        }
        return testTokens
    }
    
    func makeHashableSentFromTestToks(testTokens: [TestToken])-> HashableSentence?{
        guard testTokens.count > 0 else {return nil}
        var keepTokens: [String] = []
        for item in testTokens{
            if item.form != ""{
                keepTokens.append(item.form)
            }
        }
        let returnObject = HashableSentence(id: UUID().uuidString, tokens: keepTokens)
        for x in returnObject.tokens{
            print(x)
        }
        return returnObject
        }
        
    
    
    

}

#Preview {
    @Previewable @State var builtSents: [HashableSentence] = []
    ManualTokenisationView(builtSents: $builtSents)
}

