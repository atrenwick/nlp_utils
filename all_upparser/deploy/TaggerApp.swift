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
    @StateObject private var pipelineCache = PipelineCache()

    
    init() {
        // Ensure the runs directory exists the second the app opens
        try? PipelineServices.ResultStorageManager.getRunsDirectory()
        
    }
    

    
    var body: some Scene {
        WindowGroup {
            
            TabView{
                Tab("Config", systemImage: "book.pages.fill"){
                    PipelineSettingsView()
                }
                Tab("Settings", systemImage: "slider.horizontal.3"){
                    SetDefaultsView()
                }
//                Tab("test", systemImage: "testtube.2"){
//                    BertPipelineSettingsTestView()
//            }
            }.environmentObject(pipelineCache)
        }
    }
}


