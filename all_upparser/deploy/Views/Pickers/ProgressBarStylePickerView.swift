//
//  ProgressBarStylePickerView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI

struct ProgressBarStylePickerView: View {
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
