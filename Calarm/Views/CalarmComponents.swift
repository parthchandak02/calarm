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
    var isRefreshing: Bool = false
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
                        .frame(width: CalarmTheme.minimumTouchTarget, height: CalarmTheme.minimumTouchTarget)
                        .background(theme.toolbarIconBackground, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(theme.surfaceStroke, lineWidth: 1)
                        }
                        .contentShape(Circle())
                }
                .disabled(!canManageAlarms)
                .accessibilityLabel("Alarm bulk actions")

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.accent)
                        .frame(width: CalarmTheme.minimumTouchTarget, height: CalarmTheme.minimumTouchTarget)
                } else {
                    CalarmToolbarIconButton(
                        systemName: "arrow.clockwise",
                        theme: theme,
                        isDisabled: !canRefresh,
                        action: onRefresh
                    )
                    .accessibilityLabel("Refresh calendar")
                }

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
                .frame(width: CalarmTheme.minimumTouchTarget, height: CalarmTheme.minimumTouchTarget)
                .background(theme.toolbarIconBackground, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(theme.surfaceStroke, lineWidth: 1)
                }
                .contentShape(Circle())
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
            .padding(.horizontal, CalarmTheme.rowPaddingH)
            .frame(height: CalarmTheme.settingsRowHeight)
            .background(isSelected ? theme.accentSelected : theme.surface)
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
        .frame(height: CalarmTheme.settingsTabHeight)
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
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))

                Text(title)
                    .font(CalarmFont.captionSemibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isSelected ? theme.accentSelected : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SettingsToggleRow<Label: View>: View {
    @Binding var isOn: Bool
    let theme: CalarmTheme
    @ViewBuilder let label: () -> Label

    var body: some View {
        Toggle(isOn: $isOn) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .tint(theme.accent)
        .padding(.horizontal, CalarmTheme.rowPaddingH)
        .frame(height: CalarmTheme.settingsRowHeight)
        .background(theme.surface)
    }
}

struct SettingsActionRow: View {
    let title: String
    let theme: CalarmTheme
    var systemImage: String?
    var titleColor: Color?
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(CalarmFont.bodyMedium)
                    .foregroundStyle(titleColor ?? theme.textPrimary)

                Spacer(minLength: 8)

                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, CalarmTheme.rowPaddingH)
            .frame(height: CalarmTheme.settingsRowHeight)
            .background(theme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct SettingsInfoRow: View {
    let title: String
    let value: String
    let theme: CalarmTheme

    var body: some View {
        HStack {
            Text(title)
                .font(CalarmFont.bodyMedium)
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(CalarmFont.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, CalarmTheme.rowPaddingH)
        .frame(height: CalarmTheme.settingsRowHeight)
        .background(theme.surface)
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
