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
                        ForEach(TokenizingMethod.allCases.dropLast().sorted {$0.rawValue < $1.rawValue} ){tokMethod in
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
                        ForEach(SentencizingMethod.allCases.sorted {$0.rawValue < $1.rawValue} ){sentMethod in
                            Text(sentMethod.tidyName)
                        }
                    }
                }
                .disabled(!myConfig.parsingConfig.runResentenciser)
                .foregroundStyle(myConfig.parsingConfig.runResentenciser ? .primary : .secondary)
            }
            Section(header: Text("Pipeline Execution Steps")) {
                ForEach(PipelineStep.allCases.prefix(1)) { step in
                    let isActive = isStepActive(step)
                    Toggle(isOn: toggleBinding(for: step)) {
                        Text(step.title)
                            .foregroundColor(isActive ? .primary : .secondary)
                    }
                }
                Toggle(isOn: toggleBinding(for: PipelineStep.step3)){
                    Text("3. Lemmatisation ")
                }
                .onChange(of: myConfig.parsingConfig.getSecLems){
                    if isStepActive(PipelineStep.step3) == false && myConfig.parsingConfig.getSecLems == true {
                        myConfig.parsingConfig.maxPipelineStep = PipelineStep.step3
                    }
                }
                Toggle("    Get additional lemmas", isOn: $myConfig.parsingConfig.getSecLems)
                    .onChange(of: isStepActive(PipelineStep.step3)){
                        if isStepActive(PipelineStep.step3) == false {
                            myConfig.parsingConfig.getSecLems = false}
                    }
                Picker("    Primary method", selection: $myConfig.parsingConfig.priLemSource){
                    ForEach(LemmaSource.allCases){lsource in
                        Text(lsource.displayName)
                    }
                }
                .onChange(of: myConfig.parsingConfig.secLemSource){_, newValue in
                    if myConfig.parsingConfig.secLemSource == myConfig.parsingConfig.priLemSource {
                        if let remaining = LemmaSource.allCases.filter({ format in format != myConfig.parsingConfig.secLemSource  }).first{
                            myConfig.parsingConfig.priLemSource = remaining
                        }
                    }
                }
                Picker("    Secondary method", selection: $myConfig.parsingConfig.secLemSource){
                    ForEach(LemmaSource.allCases){lsource in
                        Text(lsource.displayName)
                    }
                }
                .onChange(of: myConfig.parsingConfig.priLemSource){_, newValue in
                    if myConfig.parsingConfig.secLemSource == myConfig.parsingConfig.priLemSource {
                        if let remaining = LemmaSource.allCases.filter({ format in format != myConfig.parsingConfig.priLemSource  }).first{
                            myConfig.parsingConfig.secLemSource = remaining
                        }
                    }
                }

                ForEach(PipelineStep.allCases.suffix(2)) { step in
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

