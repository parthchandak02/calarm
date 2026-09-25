//
//  CalarmWidgetExtensionLiveActivity.swift
//  CalarmWidgetExtension
//

import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Widget
// Flight-board style (owner's pick, 2026-09-24): pixel labels, and the countdown as flap
// tiles behind the system timer text (`FlapTimer`). The ringing screen stays AlarmKit's.
struct CalarmWidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AlarmAppMetadata>.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.88))
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
                Text(title(for: context).uppercased())
                    .font(.custom(FlapTimer.fontName, fixedSize: 11))
                    .foregroundStyle(tintColor(for: context))
                    .lineLimit(1)
                    .frame(maxWidth: 64, alignment: .leading)
            } compactTrailing: {
                CompactCountdown(context: context, tint: tintColor(for: context))
            } minimal: {
                LitSquare(tint: tintColor(for: context))
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(stateLabel(for: context))
                    .font(.custom(FlapTimer.fontName, fixedSize: 10))
                    .tracking(1.5)
                    .foregroundStyle(tintColor(for: context))
                Text(title(for: context))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let start = startLabel(for: context) {
                    Text("STARTS \(start)")
                        .font(.custom(FlapTimer.fontName, fixedSize: 9))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            BoardCountdown(context: context, style: .expanded, tint: tintColor(for: context))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text([title(for: context).uppercased(), startLabel(for: context)].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(tintColor(for: context))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(stateLabel(for: context))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.custom(FlapTimer.fontName, fixedSize: 11))
            .tracking(1.5)

            BoardCountdown(context: context, style: .lockScreen, tint: tintColor(for: context))
                .frame(maxWidth: .infinity)
        }
        .padding(14)
    }

    private func title(for context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>) -> String {
        context.attributes.metadata?.title ?? "Alarm"
    }

    /// The meeting's start. Without it a countdown that outlived its meeting reads as a
    /// phantom event; with it, it explains itself.
    private func startLabel(for context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>) -> String? {
        guard let startTimestamp = context.attributes.metadata?.eventStartTimestamp else { return nil }
        return Date(timeIntervalSince1970: startTimestamp).formatted(date: .omitted, time: .shortened).uppercased()
    }

    /// "RINGS 8:50 AM", "SNOOZED", "PAUSED", or "RINGING".
    private func stateLabel(for context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>) -> String {
        switch context.state.mode {
        case .countdown(let countdown):
            if let startTimestamp = context.attributes.metadata?.eventStartTimestamp,
               AlarmSchedulingHelpers.isSnoozeCountdown(
                   countdownFireDate: countdown.fireDate,
                   eventStart: Date(timeIntervalSince1970: startTimestamp)
               ) {
                return "SNOOZED"
            }
            return "RINGS \(countdown.fireDate.formatted(date: .omitted, time: .shortened))".uppercased()
        case .paused:
            return "PAUSED"
        case .alert:
            return "RINGING"
        @unknown default:
            return ""
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

private enum CountdownStyle {
    case lockScreen
    case expanded
    case compact

    var fontSize: CGFloat {
        switch self {
        case .lockScreen: 30
        case .expanded: 20
        case .compact: 13
        }
    }
}

private struct LitSquare: View {
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(tint)
            .frame(width: 11, height: 11)
            .shadow(color: tint.opacity(0.7), radius: 3)
    }
}

/// Compact trailing region. When iOS 27 reports a width-limited Island (landscape), there
/// is no room for digits, so it shows the lit square alone, as Apple's WWDC26 sample shows
/// an icon.
private struct CompactCountdown: View {
    let context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>
    let tint: Color

    var body: some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            LimitedWidthAware(context: context, tint: tint)
        } else {
            BoardCountdown(context: context, style: .compact, tint: tint)
        }
        #else
        BoardCountdown(context: context, style: .compact, tint: tint)
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
            LitSquare(tint: tint)
        } else {
            BoardCountdown(context: context, style: .compact, tint: tint)
        }
    }
}
#endif

private struct BoardCountdown: View {
    let context: ActivityViewContext<AlarmAttributes<AlarmAppMetadata>>
    let style: CountdownStyle
    let tint: Color

    var body: some View {
        switch context.state.mode {
        case .countdown(let countdown):
            if countdown.fireDate.timeIntervalSinceNow <= 0 {
                label("NOW")
            } else {
                // Sized from the time left at render; AlarmKit re-renders only on a state
                // change, so this can only be too wide, never clipped. No `.numericText()`
                // transition: on system timer text it can leave digits mid-animation.
                FlapTimer(
                    fireDate: countdown.fireDate,
                    fontSize: style.fontSize,
                    tint: tint,
                    showsUnits: style == .lockScreen
                )
            }
        case .paused(let paused):
            let left = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
            FlapTimer(
                text: Duration.seconds(left).formatted(.time(pattern: left >= 3_600 ? .hourMinuteSecond : .minuteSecond)),
                remaining: left,
                fontSize: style.fontSize,
                tint: tint.opacity(0.6),
                showsUnits: style == .lockScreen
            )
        case .alert:
            label(style == .compact ? "NOW" : "RINGING")
        @unknown default:
            label("-")
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.custom(FlapTimer.fontName, fixedSize: style.fontSize))
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}
