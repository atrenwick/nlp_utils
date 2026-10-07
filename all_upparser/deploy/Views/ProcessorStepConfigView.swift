//
//  ProcessorStepConfigView.swift
//  Tagger
//
//  Created by Adam on 08/09/2026.
//

import SwiftUI

struct ProcessorStepConfigViewSection: View {

    @Binding var maxActiveStep: PipelineStep
    @Binding var inputFileType: InputFileType
    @Binding var runRetokeniser: Bool
    @Binding var tokenizingMethod: TokenizingMethod
    
    var body: some View {
        Form{
            Section("Retokenisation"){
                Toggle("1. Retokenisation", isOn: $runRetokeniser)
                
                Group{
                    Picker("Tokenizing method", selection: $tokenizingMethod) {
                        ForEach(TokenizingMethod.allCases.dropLast()){tokMethod in
                            Text(tokMethod.rawValue)
                        }
                    }
                }
                .disabled(!runRetokeniser)
                .foregroundStyle(runRetokeniser ? .primary : .secondary)
            }
            Section(header: Text("Pipeline Execution Steps")) {
                ForEach(PipelineStep.allCases) { step in
                    let isActive = isStepActive(step)
                    
                    Toggle(isOn: toggleBinding(for: step)) {
                        Text(step.title)
                            .foregroundColor(isActive ? .primary : .secondary)
                    }
                }
            }
        }
    }
    private func isStepActive(_ step: PipelineStep) -> Bool {
        let maxStep = maxActiveStep
        if maxStep >= step { return true }
        return false
    }

    // Cascading reactive binding
    private func toggleBinding(for step: PipelineStep) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                isStepActive(step)
            },
            set: { isTurningOn in
                if isTurningOn {
                    // Enabling step 3 automatically turns on steps 1 & 2
                    maxActiveStep = step
                } else {
                    // Disabling step 2 drops max active step to step 1 (or nil if step 1 turned off)
                    if let previousStep = PipelineStep(rawValue: step.rawValue - 1) {
                        maxActiveStep = previousStep
                    } else {
                        maxActiveStep = .step2
                    }
                }
            }
        )
    }
}

#Preview {
    @Previewable @State var maxActiveStep: PipelineStep = .step2
    @Previewable @State var tokenizingMethod: TokenizingMethod = .nltokeniser
    @Previewable @State var inputFileType: InputFileType = .conll
    @Previewable @State var runRetokeniser: Bool = true
    ProcessorStepConfigViewSection(
        maxActiveStep: $maxActiveStep,
        inputFileType: $inputFileType,
        runRetokeniser: $runRetokeniser,
        tokenizingMethod: $tokenizingMethod
    )
}

