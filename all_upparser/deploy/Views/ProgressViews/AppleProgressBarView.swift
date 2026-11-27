//
//  ProgressBars.swift
//  moonshot
//
//  Created by Adam on 31/08/2026.
//

import Foundation
import SwiftUI

struct AppleProgressBarView: View {
    @Environment(AppModel.self) internal var model
    @Binding var myConfig: TaggerConfig
    var requestNum: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(safePercent )% completed")
                Spacer()
                Text(speedInfo.rate)
            }
            .font(.callout)
            .foregroundColor(.primary)

            let total = Double(myConfig.progressConfig.totalCount)
            let processed = Double(myConfig.progressConfig.processedCount)
            let clampedValue = total > 0 ? max(0, min(processed, total)) : 0
        
            ProgressView(value: clampedValue, total: total)
            HStack {
                Text("\(asString(processed)) of \(asString(clampedValue))")
                Spacer()
                Text(speedInfo.eta)
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
    }
}


extension AppleProgressBarView{
    struct RateData{
        let eta: String
        let rate: String
    }

    var speedInfo: RateData {
        var etaInternal = ""
        var rateInternal = ""
        if let unwrappedStartTime = myConfig.progressConfig.startTime, myConfig.progressConfig.processedCount > 0 {
            let elapsed = Date().timeIntervalSince(unwrappedStartTime)
            let rate = Double(myConfig.progressConfig.processedCount) / max(elapsed, 0.001)
            let remaining = rate > 0 ? Double(myConfig.progressConfig.totalCount - myConfig.progressConfig.processedCount) / rate : 0
            etaInternal = String(format: "ETA %ds", Int(remaining))
            rateInternal = String(format: "%.1fit/s", rate, )
        }
        return RateData(eta: etaInternal, rate: rateInternal)
    }

    var safePercent: String {
        let overallTotal = myConfig.progressConfig.totalCount * model.myConfig.parsingConfig.pipelineRequests.count
        if overallTotal == myConfig.progressConfig.processedCount {
            if myConfig.progressConfig.processedCount == 0 {return "0" } else { return "100"}
        } else {
            let tidyPercent = (Double(myConfig.progressConfig.processedCount) / Double(overallTotal) ) * 100
            return String(format: "%.1f", tidyPercent)
        }
    }

    func asString(_ number: Double)-> String{
        String(format: "%.0f", number)
    }
}
