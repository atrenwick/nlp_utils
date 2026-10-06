//
//  TaggerApp.swift
//  Tagger
//
//  Created by Adam on 06/09/2026.
//

import SwiftUI

@main
struct TaggerApp: App {
    var body: some Scene {
        WindowGroup {
            
            TabView{
                Tab("Config", systemImage: "book.pages.fill"){
                    PipelineSettingsView()
                }
                Tab("Settings", systemImage: "slider.horizontal.3"){
                    SetDefaultsView()
                }
            }
        }
    }
}
