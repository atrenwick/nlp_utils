//
//  PipelineProgressView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI

struct PipelineProcessingProgressView: View {
    @Binding var myConfig: TaggerConfig
    @Binding var currentStatus: String

    var body: some View {
        if myConfig.progressConfig.hasStarted{
            switch myConfig.progressConfig.progressBarStyle {
            case .tqdm:
                    TqdmProgressBarView(myConfig: $myConfig)
            case .apple:
                AppleProgressBarView(myConfig: $myConfig)
            }
        }
    }
}
