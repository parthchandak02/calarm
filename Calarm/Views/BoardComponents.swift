//
//  BoardComponents.swift
//  Calarm
//

import SwiftUI

/// Pixel label followed by a hairline rule: day headers on the schedule, section labels in
/// Settings.
struct BoardSectionLabel: View {
    @Environment(\.calarmTheme) private var theme

    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(CalarmFont.boardLabel)
                .tracking(2)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
            Rectangle()
                .fill(theme.surfaceStroke)
                .frame(height: 1)
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One departure-board line: a title on the left, anything on the right.
struct BoardLine<Trailing: View>: View {
    @Environment(\.calarmTheme) private var theme

    let title: String
    var detail: String?
    var titleColor: Color?
    var dotColor: Color?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CalarmFont.boardTitle)
                    .foregroundStyle(titleColor ?? theme.textPrimary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(CalarmFont.boardDetail)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(minHeight: CalarmTheme.minimumTouchTarget)
        .padding(.vertical, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.surfaceStroke.opacity(0.6))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
    }
}

extension BoardLine where Trailing == BoardValue {
    init(title: String, detail: String? = nil, value: String, valueColor: Color? = nil, showsChevron: Bool = false) {
        self.init(title: title, detail: detail) {
            BoardValue(text: value, color: valueColor, showsChevron: showsChevron)
        }
    }
}

struct BoardValue: View {
    @Environment(\.calarmTheme) private var theme

    let text: String
    var color: Color?
    var showsChevron = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(CalarmFont.boardDetail)
                .foregroundStyle(color ?? theme.textSecondary)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .fixedSize()
    }
}

/// The board's lit square: filled and glowing when on.
struct ArmSquare: View {
    @Environment(\.calarmTheme) private var theme

    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isOn ? theme.accent : Color.clear)
            .strokeBorder(isOn ? theme.accent : theme.textSecondary, lineWidth: 1.5)
            .frame(width: 18, height: 18)
            .shadow(color: isOn ? theme.accent.opacity(0.6) : .clear, radius: 6)
            .animation(.snappy, value: isOn)
            .frame(width: CalarmTheme.bellTapSize, height: CalarmTheme.bellTapSize)
            .contentShape(Rectangle())
    }
}

/// An `ArmSquare` that toggles, with a haptic.
struct ArmSquareToggle: View {
    let isOn: Bool
    let label: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ArmSquare(isOn: isOn)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A row of split-flap tiles for a single choice. Wraps at large Dynamic Type.
struct FlapPicker<Option: Hashable>: View {
    @Environment(\.calarmTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var minimumTileWidth: CGFloat = 36

    let options: [Option]
    let selection: Option
    var columns: Int?
    let tileLabel: (Option) -> String
    let accessibilityLabel: (Option) -> String
    let onSelect: (Option) -> Void

    private var gridColumns: [GridItem] {
        if let columns {
            return Array(repeating: GridItem(.flexible(), spacing: 4), count: columns)
        }
        return [GridItem(.adaptive(minimum: minimumTileWidth), spacing: 4)]
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    onSelect(option)
                } label: {
                    Text(tileLabel(option))
                        .font(CalarmFont.flapTile)
                        .foregroundStyle(isSelected ? theme.onAccent : theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: tileHeight)
                        .background(
                            isSelected ? theme.accent : theme.surface,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay {
                            Rectangle()
                                .fill(isSelected ? theme.onAccent.opacity(0.2) : theme.background)
                                .frame(height: 1)
                        }
                        .shadow(color: isSelected ? theme.accent.opacity(0.35) : .clear, radius: 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(option))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .animation(.snappy, value: selection)
    }
}

/// Amber when fine, red when not.
struct StatusLight: View {
    @Environment(\.calarmTheme) private var theme

    let isProblem: Bool

    var body: some View {
        let color = isProblem ? theme.destructive : theme.accent
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.8), radius: 4)
            .accessibilityHidden(true)
    }
}

/// Full-width board button: filled for the primary action, outlined otherwise.
struct BoardButton: View {
    @Environment(\.calarmTheme) private var theme

    let title: String
    var systemImage: String?
    var isProminent = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                }
                Text(title.uppercased())
                    .font(CalarmFont.boardLabel)
                    .tracking(2)
            }
            .foregroundStyle(isProminent ? theme.onAccent : theme.accent)
            .frame(maxWidth: .infinity, minHeight: CalarmTheme.minimumTouchTarget)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isProminent ? theme.accent : Color.clear)
                    .strokeBorder(theme.accent.opacity(isProminent ? 0 : 0.45), lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

extension View {
    /// Uppercase, tracked pixel title for board screens pushed inside a navigation stack.
    func boardNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title.uppercased())
                        .font(CalarmFont.boardTitleBar)
                        .tracking(2.5)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}
