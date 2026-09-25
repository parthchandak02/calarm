//
//  CalarmComponents.swift
//  Calarm
//

import SwiftUI
import TipKit

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
    var bulkTip: (any Tip)?
    var settingsTip: (any Tip)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(CalarmBrand.appName)
                .font(CalarmFont.headline)
                .tracking(1)
                .foregroundStyle(theme.textSecondary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
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
                        CalarmGlassIcon(
                            systemName: "bell.badge",
                            theme: theme,
                            isDisabled: !canManageAlarms
                        )
                    }
                    .disabled(!canManageAlarms)
                    .accessibilityLabel("Alarm bulk actions")
                    .popoverTip(bulkTip, arrowEdge: .top)

                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.accent)
                            .frame(width: CalarmTheme.minimumTouchTarget, height: CalarmTheme.minimumTouchTarget)
                            .glassEffect(.regular, in: .circle)
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
                        .popoverTip(settingsTip, arrowEdge: .top)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, CalarmTheme.rowPaddingH)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(theme.background)
    }
}

struct CalarmGlassIcon: View {
    let systemName: String
    let theme: CalarmTheme
    var isDisabled: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isDisabled ? theme.textSecondary : theme.toolbarIcon)
            .frame(width: CalarmTheme.minimumTouchTarget, height: CalarmTheme.minimumTouchTarget)
            .glassEffect(.regular.interactive(), in: .circle)
            .contentShape(Circle())
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
            CalarmGlassIcon(systemName: systemName, theme: theme, isDisabled: isDisabled)
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
