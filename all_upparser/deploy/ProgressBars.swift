//
//  ProgressBars.swift
//  moonshot
//
//  Created by Adam on 31/08/2026.
//

import Foundation
import SwiftUI

// enum to define names of progress bar style
enum ProgressBarStyle: String, CaseIterable, Identifiable {
    case tqdm = "tqdm"
    case apple = "Apple"

    var id: String { rawValue }
}

// the picker to change progress bar style ::
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

///  tqdm-style text line progress bar.
/// Uses the caller to track processed/total/startTime 
struct TqdmProgressView: View {
    let processed: Int
    let total: Int
    let startTime: Date?

    var body: some View {
        Text(tqdmLine())
            .font(.system(.footnote, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.6) // shrinks to fit if space is tight (e.g. inside a button)
    }

    private func tqdmLine(width: Int = 20) -> String {
        let fraction = total > 0 ? Double(processed) / Double(total) : 0
        let filled = Int(fraction * Double(width))
        let bar = String(repeating: "█", count: filled)
            + String(repeating: "-", count: max(0, width - filled))
        let percent = Int(fraction * 100)

        var rateSuffix = ""
        if let startTime, processed > 0 {
            let elapsed = Date().timeIntervalSince(startTime)
            let rate = Double(processed) / max(elapsed, 0.001)
            let remaining = rate > 0 ? Double(total - processed) / rate : 0
            rateSuffix = String(format: ", %.1fit/s, ETA %ds", rate, Int(remaining))
        }

        return "\(percent)%|\(bar)| \(processed)/\(total)\(rateSuffix)"
    }
}


/// Apple's native Progress/ProgressView, still updated manually by the
/// caller every step 
struct AppleProgressView: View {
    let progress: Progress

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(progress)
            if let description = progress.localizedDescription {
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}


/// The switcher: renders whichever style is currently selected. This 
/// goes in the view and gets passed the current state for each tracker
/// only showing one actually selected
struct PipelineProgressView: View {
    let style: ProgressBarStyle
    let processed: Int
    let total: Int
    let startTime: Date?
    let appleProgress: Progress

    var body: some View {
        switch style {
        case .tqdm:
            TqdmProgressView(processed: processed, total: total, startTime: startTime)
        case .apple:
            AppleProgressView(progress: appleProgress)
        }
    }
}
