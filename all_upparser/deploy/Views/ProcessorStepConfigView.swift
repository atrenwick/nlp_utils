//
//  ProcessorStepConfigView.swift
//  Tagger
//
//  Created by Adam on 08/09/2026.
//

import SwiftUI



struct ProcessorStepConfigViewSection: View {
    // Single source of truth from parent view (nil means all steps off)
    @Binding var maxActiveStep: PipelineStep
    @Binding var inputFileType: InputFileType
    var body: some View {
        Section(header: Text("Pipeline Execution Steps")) {
            Form{
                ForEach(PipelineStep.allCases) { step in
                    let isActive = isStepActive(step)
                    
                    Toggle(isOn: toggleBinding(for: step)) {
                        Text(step.title)
                        // Greys out text when step is off
                            .foregroundColor(isActive ? .primary : .secondary)
                    }
                }
            }
        }
        Section("Retokenisation"){
            Form{
                ForEach(InputFileType.allCases){inputFileType in
                    Text(inputFileType.rawValue)
                }
                Text("retokenisation not yet coded")
                //.onChange(of: useConllTokens) $useConllTokens=true
            }
        }
    }
    // Helper to check if a specific step is currently active
    private func isStepActive(_ step: PipelineStep) -> Bool {
         let maxStep = maxActiveStep
        if maxStep >= step {
            return true
        }
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
    @Previewable @State var inputFileType: InputFileType = .conll
    ProcessorStepConfigViewSection(maxActiveStep: $maxActiveStep, inputFileType: $inputFileType)
}

