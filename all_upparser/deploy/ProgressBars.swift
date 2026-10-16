//
//  ProgressBars.swift
//  moonshot
//
//  Created by Adam on 31/08/2026.
//

import Foundation
import SwiftUI

enum ProgressBarStyle: String, CaseIterable, Identifiable {
    case tqdm = "tqdm"
    case apple = "Apple"

    var id: String { rawValue }
}


struct ProgressBarStylePicker: View {
    @Binding var selection: ProgressBarStyle

    var body: some View {
        Picker("Progress Style", selection: $selection) {
            ForEach(ProgressBarStyle.allCases) { style in
                Text(style.rawValue).tag(style)
            }
        }
        .pickerStyle(.segmented)
    }
}


/// tqdm-style text line. uses  caller to track processed/total/startTime
struct TqdmProgressView: View {
    @Binding var myConfig: TaggerConfig

    var body: some View {
        Text(tqdmLine())
            .font(.system(.footnote, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.6) // shrinks to fit if space is tight (e.g. inside a button)
    }

    private func tqdmLine(width: Int = 20) -> String {
        let fraction = myConfig.progressConfig.totalCount > 0 ? Double(myConfig.progressConfig.processedCount) / Double(myConfig.progressConfig.totalCount) : 0
        let filled = Int(fraction * Double(width))
        let bar = String(repeating: "█", count: filled)
            + String(repeating: "-", count: max(0, width - filled))
        let percent = Int(fraction * 100)

        var rateSuffix = ""
        if let unwrappedStartTime = myConfig.progressConfig.startTime, myConfig.progressConfig.processedCount > 0 {
            let elapsed = Date().timeIntervalSince(unwrappedStartTime)
            let rate = Double(myConfig.progressConfig.processedCount) / max(elapsed, 0.001)
            let remaining = rate > 0 ? Double(myConfig.progressConfig.totalCount - myConfig.progressConfig.processedCount) / rate : 0
            rateSuffix = String(format: ", %.1fit/s, ETA %ds", rate, Int(remaining))
        }

        return "\(percent)%|\(bar)| \(myConfig.progressConfig.processedCount)/\(myConfig.progressConfig.totalCount)\(rateSuffix)"
    }
}

struct AppleProgressView: View {

    @Binding var myConfig: TaggerConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(myConfig.progressConfig.appleProgress)
//            if let description = progress.localizedDescription {
//                Text(description)
//                    .font(.caption2)
//                    .foregroundColor(.secondary)
//            }
        }
    }
}

struct PipelineProgressView: View {
    @Binding var myConfig: TaggerConfig
    var body: some View {
        
        if myConfig.progressConfig.hasStarted{
            switch myConfig.progressConfig.progressBarStyle {
            case .tqdm:
                TqdmProgressView(myConfig: $myConfig)
            case .apple:
                AppleProgressView(myConfig: $myConfig)
            }
        }
    }
}

struct RunProgressButton: View {
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
            // Use background alignment so the fill sits underneath the text/icon
            // and scales across the entire button area.
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
// button fill needs ot be faster, smoother, button filled needs ot be higher top to bottom
//    .padding()
//            .frame(maxWidth: .infinity)
//            .background(alignment: .leading) {
//                let fraction = totalCount > 0 ? CGFloat(processedCount) / CGFloat(totalCount) : 0
//                
//                Rectangle()
//                    .fill(Color.accentColor.opacity(0.3))
//                    // 1. Span full width initially
//                    .frame(maxWidth: .infinity)
//                    // 2. Scale it horizontally from the left edge (0 to 1)
//                    .scaleEffect(x: max(0, min(fraction, 1.0)), y: 1.0, anchor: .leading)
//                    // 3. Smooth animation transition
//                    .animation(.easeInOut(duration: 0.15), value: processedCount)
//            }
//            .clipShape(Capsule())
//    .frame(maxWidth: .infinity)
//            .background(alignment: .leading) {
//                // Use the native, highly optimized ProgressView
//                ProgressView(
//                    value: Double(max(0, processedCount)),
//                    total: Double(max(1, totalCount))
//                )
//                .tint(Color.accentColor.opacity(0.3)) // Adjust color and opacity of the fill
//                .scaleEffect(x: 1.0, y: 3.0, anchor: .center) // Stretches it vertically to fill the button height nicely
//            }
//            .clipShape(Capsule())
