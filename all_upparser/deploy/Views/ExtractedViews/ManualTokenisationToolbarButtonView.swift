//
//  ManualTokenisationToolbarButtonView.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI


struct ManualTokenisationToolbarButtonView: View{
     @Environment(AppModel.self) private var model

    var body: some View{
        NavigationLink {
            BuiltSentsViewer()
        } label: {
            Image(systemName: "textformat.characters.dottedunderline")
                .overlay(alignment: .topTrailing) {
                    if model.builtSents.count > 0 {
                        Text(String(model.builtSents.count))
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
