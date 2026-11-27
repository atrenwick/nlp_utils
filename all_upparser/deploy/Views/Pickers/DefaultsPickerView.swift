//
//  CustomPickers.swift
//  Tagger
//
//  Created by Adam on 16/10/2026.
//

import SwiftUI

struct DefaultPickerView<T: Hashable & CaseIterable & RawRepresentable>: View where T.RawValue == String {
    let title: String
    @Binding var selection: T
    var accessibilityLabelString: String? = nil
    var onChangeAction: ((T) -> Void)? = nil

    var body: some View {
        Picker(title, selection: $selection) {
            // 2. Iterate over all cases of whatever enum is passed in
            ForEach(filteredCases.sorted {$0.rawValue < $1.rawValue}, id: \.self) { option in
                Text (["after","before"].contains(option.rawValue) ? option.rawValue.localizedCapitalized : option.rawValue)
                    .tag(option) // 3. Automatically sets the tag
            }
        }
    }
}

extension DefaultPickerView{
    // optional to yield tokenising method if T is Tokenizing method
    var itemToDrop: T? {
        if title.contains("txt tokMethod failover") {
            // Safely attempt to cast .whale to whatever generic type T currently is
            return TokenizingMethod.trained as? T
        }
        return nil
    }

    // 2. Filter the cases using a nil check
    var filteredCases: [T] {
        if let dropItem = itemToDrop {
            // If we have an item to drop, filter it out!
            return T.allCases.filter { $0 != dropItem }
        } else {
            // Otherwise, return all cases normally (or if T is a different enum type)
            return Array(T.allCases)
        }
    }
}
