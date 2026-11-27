//
//  BigGoButtonReadinessExtractedView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//

import SwiftUI

///Show the not-ready warning messages
struct BigGoButtonReadinessExtractedView: View{
    let isPipelineReady: Bool
    let missingReqsMessage: String
    var body: some View{
            if !isPipelineReady {
                VStack{
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(missingReqsMessage)
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}
