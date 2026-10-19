//
//  ManualSentencizationView.swift
//  Tagger
//
//  Created by Adam on 09/10/2026.
//

import SwiftUI

struct ManualSentencizationView: View {
    @State var testSentsEN: String =
    """
Virgil Ivan "Gus" Grissom (April 3, 1926 - January 27, 1967) was one of the seven original National Aeronautics and Space Administration's Project Mercury astronauts, and the first of the Mercury Seven to die. He was also a Project Gemini and an Apollo program astronaut. Grissom was the second American to fly in space, and the first member of the NASA Astronaut Corps to fly in space twice.\n\nIn addition, Grissom was a World War II and Korean War veteran, U.S. Air Force test pilot, and a mechanical engineer. He was a recipient of the Distinguished Flying Cross, and the Air Medal with an oak leaf cluster, a two-time recipient of the NASA Distinguished Service Medal, and, posthumously, the Congressional Space Medal of Honor.
    Large language models (LLMs) use data to learn about the world in order to produce meaningful correlations and predictions. As such, the nature, scale, quality, and diversity of the datasets used to train these models, or to support their work at inference time, have a direct impact on their quality. The rapid development and adoption of LLMs of varying quality has brought into focus the scarcity of publicly available, high-quality training data and revealed an urgent need to ground the stewardship of these datasets in sustainable practices with clear provenance chains. To that end, this technical report introduces Institutional Books 1.0, a large collection of public domain books originally digitized through Harvard Library's participation in the Google Books project, beginning in 2006. Working with Harvard Library, we extracted, analyzed, and processed these volumes into an extensively-documented dataset of historic texts. This analysis covers the entirety of Harvard Library's collection scanned as part of that project, originally spanning 1,075,899 volumes written in over 250 different languages for a total of approximately 250 billion tokens. As part of this initial release, the OCR-extracted text (original and post-processed) as well as the metadata (bibliographic, source, and generated) of the 983,004 volumes, or 242B tokens, identified as being in the public domain have been made available. This report describes this project's goals and methods as well as the results of the analyses we performed, all in service of making this historical collection more accessible and easier for humans and machines alike to filter, read and use.
"""
    @State var testSentsFR: String = "Juliette Nadia Boulanger, née le 16 septembre 1887 dans le 9e arrondissement de Paris et morte le 22 octobre 1979 dans la même ville, est une pédagogue, pianiste, organiste, cheffe de chœur, cheffe d'orchestre et compositrice française. Elle est la sœur aînée de la compositrice Lili Boulanger. De retour en France en décembre 1829, il doit subir une quarantaine à Toulon dans un lazaret humide et glacé, ce qui aggrave sa goutte, sa tuberculose et probablement une bilharziose contractée en Égypte.\n\nIl est élu à l'Académie des inscriptions et belles-lettres après la chute de Charles X, et obtient la chaire d'Antiquité égyptienne au Collège de France. Il y donne sa leçon inaugurale en 1831. Cependant, il meurt à Paris le 4 mars 1832, à l'âge de quarante et un ans. La cause exacte de sa mort n'est pas connue (il s'agit probablement du choléra, qui s'abat sur Paris en mars). Il est enterré, selon sa volonté, non loin de son ami Joseph Fourier au cimetière du Père-Lachaise (division 18), à Paris. Le 14 mai 2017, M. Emmanuel Macron est élu président de la République."
    @State var useDouble: Bool = false
    @State var useSingle: Bool = false
    @State var foundSentsSstr: [Substring] = []
    @State var foundSentsStr: String = ""
    @State var selectedLanguage: Language = .ANG
    @State var inputString: String = "empty"
    @State var eosTokOutput: [EosTok] = []

    var body: some View {
        Form{
            Toggle(isOn: $useDouble){ Text("Use double") }
            Toggle(isOn: $useSingle){ Text("Use single") }
            Picker("Language", selection: $selectedLanguage) {
                ForEach(Language.allCases) { lang in
                    Text(lang.rawValue)
                }
            }




            HStack{
                Spacer()
//        Button {
//
//            var intermedSents: [Substring] = []
//
//            
//            for topchunk in inputString.split(separator: #"\n\n"#){
//                for schunk in topchunk.split(separator: #"\n"#){
//                    foundSentsSstr.append(schunk.replacing(#"\. "#, with: #"\.<EOS>"#))
//                }
//            }
//
//            
//            for isent in intermedSents{
//                foundSentsSstr.append(contentsOf: isent.split(separator: #"\n"#))
//            }
//        } label: { Text("Run double") }
        .buttonStyle(.borderedProminent).tint(.blue)
        Button {
            print(selectedLanguage.rawValue)
            switch selectedLanguage {
            case .FR:
                inputString = testSentsFR
                foundSentsSstr = tokeniseFR(inputString: testSentsFR, selectedLang: selectedLanguage)
                eosTokOutput = markEosEnds(selectedLanguage: .FR, tokListIn: foundSentsSstr)
            case .EN:
                inputString = testSentsEN
                foundSentsSstr = tokeniseEN(inputString: testSentsEN, selectedLanguage: selectedLanguage)
            default :
                inputString = "Use autotokenisers"
                foundSentsSstr = inputString.split(separator: " ")
            }
        } label: {
            Text("Run single")
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
            }
        }
        Form{
            ForEach(eosTokOutput){item in
                
                let printString = item.isEOS == "true" ? "\(item.form) >>>>>>>>>>>>>>>>\(item.isEOS)" : "\(item.form)"
                Text(printString)
                
            }
        }
    }
}

#Preview {
    ManualSentencizationView()
}

