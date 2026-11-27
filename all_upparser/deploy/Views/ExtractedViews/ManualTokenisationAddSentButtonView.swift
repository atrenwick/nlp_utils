//
//  ManualTokenisationAddButtonView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//

import SwiftUI

struct ManualTokenisationAddSentButtonView: View {
    let addSysName: String
    let successSymbolSysName: String
    let action: () async throws -> Void
    @State private var succeeded = false
    @State private var bounceCount = 0

    var body: some View {
        Button {
            Task {
                do {
                    try await action()
                    flashSuccess()
                } catch {
                    // handle or surface the error
                }
            }
        } label: {
            Image(systemName: succeeded ? successSymbolSysName : addSysName)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: bounceCount)
                .foregroundStyle(.green)
                .fontWeight(.bold)
        }
        .sensoryFeedback(.success, trigger: bounceCount)
    }

}
extension ManualTokenisationAddSentButtonView{
    private func flashSuccess() {
        withAnimation(.spring(duration: 0.3)) { succeeded = true }
        bounceCount += 1
    }

}
