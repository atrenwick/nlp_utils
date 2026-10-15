//
//  ProcessorStepConfigView.swift
//  Tagger
//
//  Created by Adam on 08/09/2026.
//

import SwiftUI

struct ProcessorStepConfigViewSection: View {
    @Binding var myConfig: TaggerConfig

    var body: some View {
        Form{
            Section("Retokenisation"){
                Toggle("0. Retokenisation", isOn: $myConfig.parsingConfig.runRetokeniser)
                
                Group{
                    Picker("Tokenizing method", selection: $myConfig.parsingConfig.tokenizingMethod) {
                        ForEach(TokenizingMethod.allCases.dropLast()){tokMethod in
                            Text(tokMethod.rawValue)
                        }
                    }
                }
                .disabled(!myConfig.parsingConfig.runRetokeniser)
                .foregroundStyle(myConfig.parsingConfig.runRetokeniser ? .primary : .secondary)
            }
            Section("Sentencisation"){
                Toggle("1. Resentencise", isOn: $myConfig.parsingConfig.runResentenciser)
                
                Group{
                    Picker("Sentencising method", selection: $myConfig.parsingConfig.sentencizingMethod) {
                        ForEach(SentencizingMethod.allCases){sentMethod in
                            Text(sentMethod.rawValue)
                        }
                    }
                }
                .disabled(!myConfig.parsingConfig.runResentenciser)
                .foregroundStyle(myConfig.parsingConfig.runResentenciser ? .primary : .secondary)
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
        let maxStep = myConfig.parsingConfig.maxPipelineStep
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
                    myConfig.parsingConfig.maxPipelineStep = step
                } else {
                    // Disabling step 2 drops max active step to step 1 (or nil if step 1 turned off)
                    if let previousStep = PipelineStep(rawValue: step.rawValue - 1) {
                        myConfig.parsingConfig.maxPipelineStep = previousStep
                    } else {
                        myConfig.parsingConfig.maxPipelineStep = .step2
                    }
                }
            }
        )
    }
}

#Preview {
    @Previewable @State var myConfig: TaggerConfig = TaggerConfig()
    ProcessorStepConfigViewSection(myConfig: $myConfig)
}

