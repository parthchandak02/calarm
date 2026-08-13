//
//  CalarmComponents.swift
//  Calarm
//

import SwiftUI

struct CALarmWordmark: View {
    let theme: CalarmTheme

    var body: some View {
        Text(CalarmBrand.appName)
            .font(CalarmFont.navBarWordmark)
            .foregroundStyle(theme.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ScheduleHeaderBar: View {
    let theme: CalarmTheme
    let canManageAlarms: Bool
    let allAlarmsEnabled: Bool
    let hasEnabledAlarms: Bool
    let canRefresh: Bool
    let onTurnAllOn: () -> Void
    let onTurnAllOff: () -> Void
    let onRefresh: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CALarmWordmark(theme: theme)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Menu {
                    Button(action: onTurnAllOn) {
                        Label("Turn All Alarms On", systemImage: "bell.fill")
                    }
                    .disabled(!canManageAlarms || allAlarmsEnabled)

                    Button(action: onTurnAllOff) {
                        Label("Turn All Alarms Off", systemImage: "bell.slash")
                    }
                    .disabled(!canManageAlarms || !hasEnabledAlarms)
                } label: {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canManageAlarms ? theme.toolbarIcon : theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(theme.toolbarIconBackground, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(theme.surfaceStroke, lineWidth: 1)
                        }
                }
                .disabled(!canManageAlarms)
                .accessibilityLabel("Alarm bulk actions")

                CalarmToolbarIconButton(
                    systemName: "arrow.clockwise",
                    theme: theme,
                    isDisabled: !canRefresh,
                    action: onRefresh
                )
                .accessibilityLabel("Refresh calendar")

                CalarmToolbarIconButton(systemName: "gearshape", theme: theme, action: onSettings)
                    .accessibilityLabel("Settings")
            }
            .fixedSize()
        }
        .padding(.horizontal, CalarmTheme.rowPaddingH)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(theme.background)
    }
}

struct CalarmToolbarIconButton: View {
    let systemName: String
    let theme: CalarmTheme
    let isDisabled: Bool
    let action: () -> Void

    init(
        systemName: String,
        theme: CalarmTheme,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.theme = theme
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isDisabled ? theme.textSecondary : theme.toolbarIcon)
                .frame(width: 34, height: 34)
                .background(theme.toolbarIconBackground, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(theme.surfaceStroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct SettingsOptionList<Content: View>: View {
    let theme: CalarmTheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: CalarmTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CalarmTheme.cornerRadius, style: .continuous)
                .strokeBorder(theme.surfaceStroke, lineWidth: 1)
        }
    }
}

struct SettingsOptionRow: View {
    let title: String
    let isSelected: Bool
    let theme: CalarmTheme
    let leading: AnyView?
    let action: () -> Void

    init(
        title: String,
        isSelected: Bool,
        theme: CalarmTheme,
        leading: (() -> AnyView)? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.theme = theme
        self.leading = leading?()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let leading {
                    leading
                }

                Text(title)
                    .font(CalarmFont.bodyMedium)
                    .foregroundStyle(theme.textPrimary)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? theme.accent.opacity(0.1) : theme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SettingsSectionHeader: View {
    let title: String
    let theme: CalarmTheme

    var body: some View {
        Text(title)
            .font(CalarmFont.sectionHeader)
            .foregroundStyle(theme.textSecondary)
            .textCase(.uppercase)
            .tracking(CalarmTheme.sectionHeaderTracking)
    }
}

struct SettingsTabBar<Tab: SettingsTabItem>: View {
    @Binding var selection: Tab
    let theme: CalarmTheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Tab.allCases.enumerated()), id: \.element.id) { index, tab in
                SettingsTabButton(
                    title: tab.title,
                    systemImage: tab.systemImage,
                    isSelected: selection == tab,
                    theme: theme
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = tab
                    }
                }
                .accessibilityIdentifier(tab.accessibilityIdentifier)

                if index < Tab.allCases.count - 1 {
                    Rectangle()
                        .fill(theme.surfaceStroke)
                        .frame(width: 1)
                }
            }
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CalarmTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CalarmTheme.cornerRadius, style: .continuous)
                .strokeBorder(theme.surfaceStroke, lineWidth: 1)
        }
        .accessibilityIdentifier("settings.tabBar")
    }
}

private struct SettingsTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let theme: CalarmTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))

                Text(title)
                    .font(CalarmFont.captionSemibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(isSelected ? theme.accent.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

protocol SettingsTabItem: CaseIterable, Equatable, Identifiable {
    var title: String { get }
    var systemImage: String { get }
    var accessibilityIdentifier: String { get }
}

struct AccentColorDot: View {
    let accent: CalarmAccent
    let theme: CalarmTheme

    var body: some View {
        Circle()
            .fill(accent.color.gradient)
            .frame(width: 22, height: 22)
            .overlay {
                Circle()
                    .strokeBorder(theme.surfaceStroke, lineWidth: 1)
            }
    }
}
