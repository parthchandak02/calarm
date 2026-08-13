//
//  CalarmWidgetExtensionLiveActivity.swift
//  CalarmWidgetExtension
//

import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Widget
struct CalarmWidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AlarmAppMetadata>.self) { context in
            if isActivityExpired(context: context) {
                EmptyView()
            } else {
                lockScreenView(context: context)
                    .activitySystemActionForegroundColor(tintColor(for: context))
                    .widgetURL(deepLinkURL(for: context))
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // Keep expanded content in one region so iOS does not stretch a sparse
                // leading/trailing layout into a full-width empty pill.
                DynamicIslandExpandedRegion(.center) {
                    expandedIslandContent(for: context)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .font(.caption)
                    .foregroundStyle(tintColor(for: context))
            } compactTrailing: {
                countdownLabel(for: context, style: .compact)
                    .frame(width: 58, alignment: .trailing)
                    .clipped()
            } minimal: {
                Image(systemName: "alarm.fill")
                    .font(.caption2)
                    .foregroundStyle(tintColor(for: context))
            }
            .contentMargins(.horizontal, 8, for: .compactTrailing)
            .contentMargins(.horizontal, 12, for: .expanded)
            .keylineTint(tintColor(for: context))
            .widgetURL(deepLinkURL(for: context))
        }
    }

    @ViewBuilder
    private func expandedIslandContent(
        for context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "alarm.fill")
                .foregroundStyle(tintColor(for: context))

            Text(context.attributes.metadata?.title ?? "Alarm")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 4)

            countdownLabel(for: context, style: .expanded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.headline)
                .foregroundStyle(tintColor(for: context))

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.metadata?.title ?? "Alarm")
                    .font(.headline)
                    .foregroundStyle(.primary)

                countdownLabel(for: context, style: .lockScreen)
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    private enum CountdownStyle {
        case lockScreen
        case expanded
        case compact
    }

    @ViewBuilder
    private func countdownLabel(
        for context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>,
        style: CountdownStyle
    ) -> some View {
        let tint = tintColor(for: context)

        switch context.state.mode {
        case .countdown(let countdown):
            let fireDate = countdown.fireDate
            if fireDate.timeIntervalSinceNow <= 0 {
                EmptyView()
            } else {
                let showsHours = fireDate.timeIntervalSinceNow >= 3_600
                Text(timerInterval: Date.now...fireDate, countsDown: true, showsHours: showsHours)
                    .font(font(for: style))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.numericText())
                    .frame(width: style == .compact ? 58 : nil, alignment: .trailing)
            }
        case .paused:
            Text("Paused")
                .font(font(for: style))
                .foregroundStyle(tint.opacity(0.85))
                .lineLimit(1)
                .frame(width: style == .compact ? 58 : nil, alignment: .trailing)
        case .alert:
            Text("Alerting")
                .font(font(for: style))
                .foregroundStyle(tint)
                .lineLimit(1)
                .frame(width: style == .compact ? 58 : nil, alignment: .trailing)
        @unknown default:
            Text("—")
                .font(font(for: style))
                .foregroundStyle(.secondary)
        }
    }

    private func isActivityExpired(context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>) -> Bool {
        if let endTimestamp = context.attributes.metadata?.eventEndTimestamp {
            return Date().timeIntervalSince1970 >= endTimestamp
        }

        if case .countdown(let countdown) = context.state.mode {
            return countdown.fireDate.timeIntervalSinceNow <= 0
        }

        return false
    }

    private func font(for style: CountdownStyle) -> Font {
        switch style {
        case .lockScreen:
            return .system(.caption, design: .rounded).monospacedDigit()
        case .expanded:
            return .system(.body, design: .rounded).monospacedDigit()
        case .compact:
            return .system(size: 11, weight: .semibold, design: .rounded).monospacedDigit()
        }
    }

    /// AlarmKit exposes the app-chosen accent on `AlarmAttributes.tintColor` (ActivityKit).
    private func tintColor(for context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>) -> Color {
        context.attributes.tintColor
    }

    private func deepLinkURL(for context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>) -> URL? {
        guard let eventID = context.attributes.metadata?.eventID else { return nil }
        return CalarmDeepLink.eventURL(occurrenceID: eventID)
    }
}
