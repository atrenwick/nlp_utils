//
//  PrebuiltSentsView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI


struct PrebuiltSentsView: View {
    @Binding var newSentence: String
//    @State var showSuccess: Bool = false
    let testSents: [String]
    var body: some View{
        Form{
            ForEach(testSents, id:\.self){testSentence in
                HStack{
                    Text(testSentence)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                    ManualTokenisationAddSentButtonView(addSysName: "plus.circle", successSymbolSysName: "checkmark.circle.fill"){
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
