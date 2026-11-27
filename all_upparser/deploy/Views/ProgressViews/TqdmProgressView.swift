//
//  TqdmProgressView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI

/// tqdm-style text line. uses  caller to track processed/total/startTime
struct TqdmProgressBarView: View {
    @Binding var myConfig: TaggerConfig

    var body: some View {
        Text(tqdmLine())
            .font(.system(.footnote, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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
