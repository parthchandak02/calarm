//
//  AlarmOffsetListPicker.swift
//  Calarm
//

import SwiftUI

struct AlarmOffsetListPicker: View {
    let options: [AlarmOffsetOption]
    let selected: AlarmOffsetOption?
    let theme: CalarmTheme
    let onSelect: (AlarmOffsetOption) -> Void

    var body: some View {
        SettingsOptionList(theme: theme) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                SettingsOptionRow(
                    title: option.title,
                    isSelected: selected == option,
                    theme: theme
                ) {
                    onSelect(option)
                }

                if index < options.count - 1 {
                    Divider().overlay(theme.surfaceStroke)
                }
            }
        }
    }
}

struct AlarmOffsetSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [AlarmOffsetOption]
    let theme: CalarmTheme
    let onSelect: (AlarmOffsetOption) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AlarmOffsetListPicker(
                        options: options,
                        selected: nil,
                        theme: theme
                    ) { option in
                        onSelect(option)
                        dismiss()
                    }
                }
                .padding(20)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(CalarmFont.bodyMedium)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }
}
