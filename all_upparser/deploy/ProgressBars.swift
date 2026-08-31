//
//  ProgressBars.swift
//  moonshot
//
//  Created by Adam on 31/08/2026.
//

import Foundation
import SwiftUI

//  A picker-selectable choice between the two progress-reporting styles
//  explored in ProgressBarComparisonView, plus reusable views for each so
//  they can be dropped into any view (like a button label) and switched
//  live via the enum.
//


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

/// Hand-rolled tqdm-style text line. Needs the caller to track
/// processed/total/startTime itself (see runTest()'s rewrite).
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
/// caller every step (see runTest()'s rewrite) -- there's no auto-tracking
/// for a plain processing loop, only the native rendering is "free" here.
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


/// The switcher: renders whichever style is currently selected. This is
/// the one you actually place in your view -- pass it both trackers'
/// current state and it picks which to show.
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
