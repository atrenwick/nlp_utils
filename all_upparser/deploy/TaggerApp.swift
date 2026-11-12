//
//  TaggerApp.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
//

import SwiftUI
import Combine

@main
struct TaggerApp: App {
    @State var model = AppModel()
    
    init() {
        // Ensure the runs directory exists the second the app opens
        try? PipelineServices.ResultStorageManager.getRunsDirectory()
    }
    
    var body: some Scene {
        WindowGroup {
            
            TabView{
                Tab("Config", systemImage: "house"){
                    PipelineSettingsView()
                }
                Tab("Outputs", systemImage: "book.pages.fill"){
                    RunOutputView()
                }
            }
            
            .environment(model)
        }
    }
}

