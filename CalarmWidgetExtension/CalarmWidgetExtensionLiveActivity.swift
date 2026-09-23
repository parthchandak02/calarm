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
                CompactCountdown(context: context, tint: tintColor(for: context))
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

            VStack(alignment: .leading, spacing: 1) {
                Text(context.attributes.metadata?.title ?? "Alarm")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let caption = caption(for: context) {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            CountdownText(context: context, style: .expanded, tint: tintColor(for: context))
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

                if let caption = caption(for: context) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                CountdownText(context: context, style: .lockScreen, tint: tintColor(for: context))
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    /// "Starts 9:00 AM", or "Snoozed · starts 9:00 AM". Without the start time a countdown
    /// that outlived its meeting reads as a phantom event; with it, it explains itself.
    private func caption(for context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>) -> String? {
        guard let startTimestamp = context.attributes.metadata?.eventStartTimestamp else { return nil }
        let start = Date(timeIntervalSince1970: startTimestamp)
        let time = start.formatted(date: .omitted, time: .shortened)
        if case .countdown(let countdown) = context.state.mode,
           AlarmSchedulingHelpers.isSnoozeCountdown(countdownFireDate: countdown.fireDate, eventStart: start) {
            return "Snoozed · starts \(time)"
        }
        return "Starts \(time)"
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

private enum CountdownStyle {
    case lockScreen
    case expanded
    case compact

    var font: Font {
        switch self {
        case .lockScreen:
            .system(.caption, design: .rounded).monospacedDigit()
        case .expanded:
            .system(.body, design: .rounded).monospacedDigit()
        case .compact:
            .system(size: 11, weight: .semibold, design: .rounded).monospacedDigit()
        }
    }
}

/// Compact trailing region. When iOS 27 reports a width-limited Island (landscape), there
/// is no room for digits, so it shows the icon alone, as Apple's WWDC26 sample does.
private struct CompactCountdown: View {
    let context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>
    let tint: Color

    var body: some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            LimitedWidthAware(context: context, tint: tint)
        } else {
            CountdownText(context: context, style: .compact, tint: tint)
        }
        #else
        CountdownText(context: context, style: .compact, tint: tint)
        #endif
    }
}

// The iOS 27 SDK (Xcode 27, Swift 6.4) is the first with this environment value. The
// release Mac builds with Xcode 26, so the check has to compile away there.
#if compiler(>=6.4)
@available(iOS 27.0, *)
private struct LimitedWidthAware: View {
    let context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>
    let tint: Color
    @Environment(\.isDynamicIslandLimitedInWidth) private var isLimitedInWidth

    var body: some View {
        if isLimitedInWidth {
            Image(systemName: "timer")
                .font(.caption)
                .foregroundStyle(tint)
        } else {
            CountdownText(context: context, style: .compact, tint: tint)
        }
    }
}
#endif

private struct CountdownText: View {
    let context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>
    let style: CountdownStyle
    let tint: Color

    var body: some View {
        switch context.state.mode {
        case .countdown(let countdown):
            let fireDate = countdown.fireDate
            let remaining = fireDate.timeIntervalSinceNow
            if remaining <= 0 {
                Text("Now")
                    .font(style.font)
                    .foregroundStyle(tint)
                    .lineLimit(1)
            } else {
                // Sized from the time left at render. The timer reserves its width once per
                // render and AlarmKit re-renders only on a state change, so the pill cannot
                // shrink mid-countdown; but remaining time only falls, so this can only be
                // too wide, never clipped. No `.numericText()` transition: on system timer
                // text it can leave digits mid-animation in the Island.
                Text(timerInterval: Date.now...fireDate, countsDown: true, showsHours: remaining >= 3_600)
                    .font(style.font)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(
                        width: style == .compact
                            ? CGFloat(AlarmSchedulingHelpers.compactCountdownWidth(remaining: remaining))
                            : nil,
                        alignment: .trailing
                    )
            }
        case .paused(let paused):
            Text(pausedLabel(paused))
                .font(style.font)
                .foregroundStyle(tint.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        case .alert:
            Text(style == .compact ? "Now" : "Alerting")
                .font(style.font)
                .foregroundStyle(tint)
                .lineLimit(1)
        @unknown default:
            Text("-")
                .font(style.font)
                .foregroundStyle(.secondary)
        }
    }

    private func pausedLabel(_ paused: AlarmPresentationState.Mode.Paused) -> String {
        let left = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
        let formatted = Duration.seconds(left).formatted(
            .time(pattern: left >= 3_600 ? .hourMinuteSecond : .minuteSecond)
        )
        return style == .compact ? formatted : "Paused · \(formatted)"
    }
}
