//
//  ArchitecturePickerView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//

import SwiftUI

    /// Customised Architecture picker for model architectures, with onChange modifiers
struct ArchitecturePickerView: View{
    @Environment(AppModel.self) private var model
    
    var body: some View {
        @Bindable var model = model
        Picker("Architecture", selection: $model.myConfig.parsingConfig.modelArchitecture){
            ForEach(ModelArchitecture.allCases.sorted {$0.rawValue < $1.rawValue }){modarch in
                Text(modarch.displayName)
            }
        }.onChange(of: model.myConfig.parsingConfig.modelArchitecture){
            if model.myConfig.parsingConfig.modelArchitecture == .distilbert && model.myConfig.inputConfig.inputFileType == .txt {model.myConfig.parsingConfig.tokenizingMethod = .nltokeniser}
        }
    }
}

