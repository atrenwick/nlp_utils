//
//  ProcessorStepConfigView.swift
//  Tagger
//
//  Created by Adam on 08/09/2026.
//

import SwiftUI



struct ProcessorStepConfigView: View {
    // Single source of truth from parent view (nil means all steps off)
    @Binding var maxActiveStep: PipelineStep?
    @Binding var inputFileType: InputFileType
    @State var useConllTokens: Bool = true
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
        Section("Tokenisation"){
            Form{
                Toggle(isOn: $useConllTokens){
                    Text("Use \(inputFileType) tokenisation")}
                //.onChange(of: useConllTokens) $useConllTokens=true
                
            }
        }
    }
    // Helper to check if a specific step is currently active
    private func isStepActive(_ step: PipelineStep) -> Bool {
        if let maxStep = maxActiveStep {
            return maxStep >= step
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
                        maxActiveStep = nil
                    }
                }
            }
        )
    }
}

#Preview {
    @Previewable @State var maxActiveStep: PipelineStep? = .step2
    @Previewable @State var inputFileType: InputFileType = .conll
    ProcessorStepConfigView(maxActiveStep: $maxActiveStep, inputFileType: $inputFileType)
}

enum PipelineStep: Int, CaseIterable, Identifiable, Comparable {
    // RawValue type (Int) links each case to an integer (1, 2, 3, 4).
    // Comparable conformance allows using <, >, <=, >= on enum cases.
    case step1 = 1
    case step2 = 2
    case step3 = 3
    case step4 = 4
    
    // raw value = id, to conform to Identifiable
    var id: Int { rawValue }
    
    // Computed property: evaluates 'self' on demand and returns the matching  string
    var title: String {
        switch self {
        case .step1: return "1. POS tagging"
        case .step2: return "2. Lemmatisation"
        case .step3: return "3. Feats"
        case .step4: return "4. DepParse"
        }
    }
    // required for Comparable : Swift expects this to build other comparison operattions
    static func < (lhs: PipelineStep, rhs: PipelineStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
