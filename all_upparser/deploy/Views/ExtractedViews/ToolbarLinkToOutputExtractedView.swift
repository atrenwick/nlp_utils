//
//  ToolbarLinkToOutputExtractedView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI

/// Navigation link + image to RunOutput view
struct ToolbarLinkToOutputExtractedView: View {
    var unreadCount: Int = 0
    var body: some View{
        
        NavigationLink{
            RunOutputView()
        } label: {
            Image(systemName: "book.pages.fill")
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        Text(String(unreadCount))
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(.red))
                            .offset(x: 8, y: -8)
                    }
                }
        }
    }
}
