//
//  ProcessorStepConfigView.swift
//  Tagger
//
//  Created by Adam on 08/09/2026.
//
import SwiftUI

struct ProcessorStepConfigViewSection: View {
     @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form{
            Section("Retokenisation"){
                Toggle("0. Retokenisation", isOn: $model.myConfig.parsingConfig.runRetokeniser)
                
                Group{
                    Picker("Tokenizing method", selection: $model.myConfig.parsingConfig.tokenizingMethod) {
                        ForEach(TokenizingMethod.allCases.dropLast().sorted {$0.rawValue < $1.rawValue} ){tokMethod in
                            Text(tokMethod.rawValue)
                        }
                    }
                }
                .disabled(!model.myConfig.parsingConfig.runRetokeniser)
                .foregroundStyle(model.myConfig.parsingConfig.runRetokeniser ? .primary : .secondary)
            }
            Section("Sentencisation"){
                Toggle("1. Resentencise", isOn: $model.myConfig.parsingConfig.runResentenciser)
                Group{
                    Picker("Sentencising method", selection: $model.myConfig.parsingConfig.sentencizingMethod) {
                        ForEach(SentencizingMethod.allCases.sorted {$0.rawValue < $1.rawValue} ){sentMethod in
                            Text(sentMethod.tidyName)
                        }
                    }
                }
                .disabled(!model.myConfig.parsingConfig.runResentenciser)
                .foregroundStyle(model.myConfig.parsingConfig.runResentenciser ? .primary : .secondary)
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
                .onChange(of: model.myConfig.parsingConfig.getSecLems){
                    if isStepActive(PipelineStep.step3) == false && model.myConfig.parsingConfig.getSecLems == true {
                        model.myConfig.parsingConfig.maxPipelineStep = PipelineStep.step3
                    }
                }
                Toggle("    Get additional lemmas", isOn: $model.myConfig.parsingConfig.getSecLems)
                    .onChange(of: isStepActive(PipelineStep.step3)){
                        if isStepActive(PipelineStep.step3) == false {
                            model.myConfig.parsingConfig.getSecLems = false}
                    }
                Picker("    Primary method", selection: $model.myConfig.parsingConfig.priLemSource){
                    ForEach(LemmaSource.allCases){lsource in
                        Text(lsource.displayName)
                    }
                }
                .onChange(of: model.myConfig.parsingConfig.secLemSource){_, newValue in
                    if model.myConfig.parsingConfig.secLemSource == model.myConfig.parsingConfig.priLemSource {
                        if let remaining = LemmaSource.allCases.filter({ format in format != model.myConfig.parsingConfig.secLemSource  }).first{
                            model.myConfig.parsingConfig.priLemSource = remaining
                        }
                    }
                }
                Picker("    Secondary method", selection: $model.myConfig.parsingConfig.secLemSource){
                    ForEach(LemmaSource.allCases){lsource in
                        Text(lsource.displayName)
                    }
                }
                .onChange(of: model.myConfig.parsingConfig.priLemSource){_, newValue in
                    if model.myConfig.parsingConfig.secLemSource == model.myConfig.parsingConfig.priLemSource {
                        if let remaining = LemmaSource.allCases.filter({ format in format != model.myConfig.parsingConfig.priLemSource  }).first{
                            model.myConfig.parsingConfig.secLemSource = remaining
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
        let maxStep = model.myConfig.parsingConfig.maxPipelineStep
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
                    model.myConfig.parsingConfig.maxPipelineStep = step
                } else {
                    // Disabling step 2 drops max active step to step 1 (or nil if step 1 turned off)
                    if let previousStep = PipelineStep(rawValue: step.rawValue - 1) {
                        model.myConfig.parsingConfig.maxPipelineStep = previousStep
                    } else {
                        model.myConfig.parsingConfig.maxPipelineStep = .step2
                    }
                }
            }
        )
    }
}

#Preview {
//    @Previewable @State var previewConfig: TaggerConfig = TaggerConfig()
    ProcessorStepConfigViewSection().environment(AppModel())
}
