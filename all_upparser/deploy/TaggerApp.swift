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
                Tab("Main", systemImage: "book.pages.fill"){
                    ContentView()
                }
            }
        }
    }
}
