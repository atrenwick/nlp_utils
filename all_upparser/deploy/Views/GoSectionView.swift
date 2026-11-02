//
//  GoSection.swift
//  Tagger
//
//  Created by Adam on 02/11/2026.
//
import SwiftUI
internal import UniformTypeIdentifiers

struct GoSectionUpperHalf: View{
    @Binding var myConfig: TaggerConfig
    @Binding var currentStatus: String
    let isPipelineReady: Bool
    let missingReqsMessage: String
    @Binding var isLoading: Bool
    let loadTotal: Int
    @Binding var loadedCount: Int
    @Binding var loadStatus: String

    var body: some View {
            BigGoButtonReadinessExtractedView(
                isPipelineReady: isPipelineReady,
                missingReqsMessage: missingReqsMessage
            )
            if isLoading {
                VStack {
                    ProgressView(
                        value: isLoading ? Double(loadedCount) : 0.0,
                        total: Double(loadTotal)
                    )
                    Text(loadStatus)
                }
            }
            PipelineProgressView(myConfig: $myConfig, currentStatus: $currentStatus)
        }
}

