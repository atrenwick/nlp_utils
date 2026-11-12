//
//  MultiParseConfigurationView.swift
//  Tagger
//
//  Created by Adam on 11/11/2026.
//

import SwiftUI

struct MultiParseConfigurationView: View {
    @Environment(AppModel.self) private var model
    
    var isMultiMode: Binding<Bool>{
        Binding(
            get: {model.currentMode == .multi}, // check whether the currentMode is equal to multi. If it is, we're in multimode, so this will give True. // enum to Bool translation
            set: { model.currentMode = $0 ? .multi : .single} // to SET, look at the new value, $0 ; if this new value is True, return multi, else, single
        )
    }
    var body: some View {
        @Bindable var model = model
        NavigationStack{
            Form{
                Toggle("Activate multiparse mode", isOn: isMultiMode)
                Section{
                    ArchitecturePickerView()
                    ConstrainedPickerForLang()
                    ConstrainedPickerForTB()
                    HStack{
                        Spacer()
                        Button{
                            addCurrentConfig()
                        } label: {
                            Text("Add")
                        }.buttonStyle(.borderedProminent)
                    }
                }
                Section{
                    ForEach(model.myConfig.parsingConfig.pipelineRequests){item in
                        Text(item.description)
                    
                    .contentShape(Rectangle())
                    .swipeActions(edge: .trailing){
                        Button(role: .destructive){
                            model.myConfig.parsingConfig.pipelineRequests.removeAll(where: {$0.description == item.description})
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    }
                }
            }.navigationTitle("Multiparse mode")
        }
    }
    func addCurrentConfig(){
        let newRequest = PipelineBuildRequest(
            languageCode: model.myConfig.parsingConfig.selectedLanguage,
            base: model.myConfig.parsingConfig.modelArchitecture,
            treebank: model.myConfig.parsingConfig.selectedTreebank
        )
        model.myConfig.parsingConfig.pipelineRequests.append(newRequest)
    }
}

#Preview {
//    @Previewable @State var PreviewConfig: TaggerConfig = TaggerConfig()
    MultiParseConfigurationView().environment(AppModel())
}
