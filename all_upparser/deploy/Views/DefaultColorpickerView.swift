//
//  DefaultColorPickerView.swift
//  Tagger
//
//  Created by Adam on 05/11/2026.
//

import SwiftUI

// Pickers to set default colours for Pipeline currently cached/not cached, save to @AppStorage
struct DefaultColorPickerView: View {
    @AppStorage("buttonColor1Default") var buttonColor1DefaultData: Data = (try? JSONEncoder().encode(StoredColor(.green, name: "Button Color: Use cached pipe"))) ?? Data()
    @AppStorage("buttonColor2Default") var buttonColor2DefaultData: Data = (try? JSONEncoder().encode(StoredColor(.blue, name: "Button Color: Load new"))) ?? Data()

    var body: some View {
            ColorPicker(label(buttonColor1DefaultData, "fallbackNameForView"),
                        selection: color($buttonColor1DefaultData, name: "fallbackNameInFunc", fallback: .yellow))
            ColorPicker(label(buttonColor2DefaultData, "fallbackNameForView"),
                        selection: color($buttonColor2DefaultData, name: "fallbackNameInFunc", fallback: .yellow))
    }
    
    func color(_ data: Binding<Data>, name: String, fallback: Color) -> Binding<Color> {
        Binding(
            get: { stored(data.wrappedValue)?.color ?? fallback },
            set: { newColor in
                let keptName = stored(data.wrappedValue)?.name  ?? name
                data.wrappedValue = (try? JSONEncoder().encode(StoredColor(newColor, name: keptName)))
                ?? data.wrappedValue
            }
        )
    }
    func stored(_ data: Data) -> StoredColor? {
        try? JSONDecoder().decode(StoredColor.self, from: data)
    }
    func label(_ data: Data, _ defaultName: String) -> String {
        stored(data)?.name ?? defaultName
    }
}
#Preview {
    DefaultColorPickerView()
}

