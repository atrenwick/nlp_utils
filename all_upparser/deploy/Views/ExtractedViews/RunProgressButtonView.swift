//
//  RunProgressButtonView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI

struct RunProgressButtonView: View {
    let processed: Int
    let total: Int
    let taggingInProgress: Bool
    let isPipelineReady: Bool
    let inputFileType: InputFileType
    let maxPipelineStep: PipelineStep
    
    var body: some View {
        HStack {
            Image(systemName: taggingInProgress ? "hourglass" : "play.fill")
            Text(taggingInProgress ? "(\(processed)/\(total))" : "Run")
                .fontWeight(.semibold)
            Spacer()
        }.opacity(taggingInProgress ? 0.5 : 1)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(alignment: .leading)  {
                GeometryReader { geometry in
                    let fraction = total > 0 ? CGFloat(processed) / CGFloat(total) : 0
                    Rectangle()
                        .fill(Color.accentColor.opacity(1)) // Adjust fill color/opacity
                        .frame(width: geometry.size.width * max(0, min(fraction, 1.0)))
                        .animation(.linear(duration: 0.01), value: processed)
                }
            }
            .clipShape(Capsule())
    }
}
