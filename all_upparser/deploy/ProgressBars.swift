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
    @Binding var currentStatus: String

    var body: some View {
//        HStack{
//            Text("Status = \(currentStatus)")
//        }
//        
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
//    @Binding var currentStatus: String
    
    var body: some View {
//        Text(currentStatus)
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
