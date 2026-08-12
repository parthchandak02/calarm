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
            lockScreenView(context: context)
                .activitySystemActionForegroundColor(tintColor(for: context))
                .widgetURL(deepLinkURL(for: context))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "alarm.fill")
                            .foregroundStyle(tintColor(for: context))
                        Text(context.attributes.metadata?.title ?? "Alarm")
                            .font(.headline)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    countdownLabel(for: context, style: .expanded)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .font(.caption)
                    .foregroundStyle(tintColor(for: context))
            } compactTrailing: {
                countdownLabel(for: context, style: .compact)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .font(.caption2)
                    .foregroundStyle(tintColor(for: context))
            }
            .keylineTint(tintColor(for: context))
            .widgetURL(deepLinkURL(for: context))
        }
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
                    .minimumScaleFactor(0.85)
                    .contentTransition(.numericText())
                    .frame(maxWidth: style == .compact ? .infinity : nil, alignment: .trailing)
            }
        case .paused:
            Text("Paused")
                .font(font(for: style))
                .foregroundStyle(tint.opacity(0.85))
        case .alert:
            Text("Alerting")
                .font(font(for: style))
                .foregroundStyle(tint)
        @unknown default:
            Text("—")
                .font(font(for: style))
                .foregroundStyle(.secondary)
        }
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
