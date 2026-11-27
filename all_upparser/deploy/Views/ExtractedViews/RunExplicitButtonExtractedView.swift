//
//  RunExplicitButtonExtractedView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI


///View for set of buttons to run test load functions
struct RunExplicitButtonExtractedView: View{
    @Environment(AppModel.self) private var model
    @State var outputString: String = "not yet run"
    
    var body: some View{
        if model.myConfig.parsingConfig.verbosity.rawValue > 0{
            HStack{
                Button {
                    //                    outputString = testInstantiatePipeline(myConfig: myConfig)
                } label: {
                    Text("Test load")
                }
                .tint(.orange)
                .buttonStyle(.borderedProminent)
                
                Button {
                    outputString = "reset"
                } label: {
                    Text("reset")
                }
                .tint(.blue)
                .buttonStyle(.borderedProminent)
                
                Text("Use \(model.myConfig.parsingConfig.selectedLanguage.displayName) \(model.myConfig.parsingConfig.selectedTreebank.short)")
                Text(outputString)
            }
        }
    }
}
