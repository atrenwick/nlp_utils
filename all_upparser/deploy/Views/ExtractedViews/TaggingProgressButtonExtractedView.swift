//
//  TaggingProgressButtonExtractedView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//

import SwiftUI


/// visual of the button to push to run the pipeline
struct TaggingProgressButtonExtractedView: View{
    @Environment(AppModel.self) private var model

    let taggingInProgress: Bool
    @Binding var currentPipelineDesc: PipelineDesc?
    @Binding var currentPipelineLoaded: Bool
    var previous: Int = 0

    var body: some View {
        Group {
            VStack {
                HStack {
                    Image(systemName: taggingInProgress ? "progress.indicator" : "play.fill")
                        .symbolEffect(.rotate, options: .repeating, isActive: taggingInProgress)
                    Text(taggingInProgress ? "Running" : "Run")
                        .fontWeight(.semibold)
                }
                if currentPipelineLoaded, let loadedDesc = currentPipelineDesc {
                    HStack{
                        Text(loadedDesc.lang.uppercased())
                        Spacer()
                        Text(loadedDesc.tb)
                        Spacer()
                        Text(loadedDesc.llm)
                        Spacer()
                        Text(loadedDesc.tok)
                    }
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}
