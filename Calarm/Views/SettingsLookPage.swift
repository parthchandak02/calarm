//
//  SettingsLookPage.swift
//  Calarm
//

import SwiftUI

struct SettingsLookPage: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.calarmTheme) private var theme

    private let sampleCalendarColor = Color(red: 0.31, green: 0.55, blue: 1)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                preview
                    .padding(.top, 8)

                BoardSectionLabel(title: "Accent")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                    ForEach(CalarmAccent.allCases) { choice in
                        accentSwatch(choice)
                    }
                }
                .sensoryFeedback(.selection, trigger: themeStore.accent)

                BoardSectionLabel(title: "Appearance")
                FlapPicker(
                    options: CalarmAppearance.allCases,
                    selection: themeStore.appearance,
                    columns: 3,
                    tileLabel: { $0.title.uppercased() },
                    accessibilityLabel: \.title,
                    onSelect: { themeStore.appearance = $0 }
                )

                BoardSectionLabel(title: "Dynamic Island")
                BoardLine(title: "Use each calendar’s colour", detail: "Instead of the accent, on the Island and Lock Screen") {
                    ArmSquareToggle(
                        isOn: themeStore.useCalendarColorInLiveActivity,
                        label: "Use each calendar’s colour"
                    ) {
                        themeStore.useCalendarColorInLiveActivity.toggle()
                    }
                }
                .accessibilityIdentifier("settings.liveActivity.useCalendarColor")
            }
            .padding(.horizontal, CalarmTheme.rowPaddingH)
            .padding(.bottom, 24)
        }
        .boardNavigationTitle("Look")
    }

    /// A schedule row and the compact Island, redrawn live as the choices change.
    private var preview: some View {
        let islandTint = themeStore.useCalendarColorInLiveActivity ? sampleCalendarColor : theme.accent
        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("09:00")
                    .font(CalarmFont.time)
                Text("Standup")
                    .font(CalarmFont.boardTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("−10m")
                    .font(CalarmFont.boardDetail)
                ArmSquare(isOn: true)
                    .frame(width: 24, height: 24)
            }
            .foregroundStyle(theme.accent)

            HStack {
                Text("STANDUP")
                Spacer()
                Text("42:10")
            }
            .font(CalarmFont.boardLabel)
            .tracking(1)
            .foregroundStyle(islandTint)
            .padding(.horizontal, 14)
            .frame(width: 200, height: 32)
            .background(.black, in: Capsule())
        }
        .padding(12)
        .background(theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.surfaceStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview")
    }

    private func accentSwatch(_ choice: CalarmAccent) -> some View {
        let isSelected = themeStore.accent == choice
        return Button {
            themeStore.accent = choice
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(choice.color)
                .aspectRatio(1, contentMode: .fit)
                .padding(isSelected ? 3 : 0)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(choice.color, lineWidth: 1.5)
                    }
                }
                .shadow(color: isSelected ? choice.color.opacity(0.6) : .clear, radius: 6)
                .frame(minHeight: CalarmTheme.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
