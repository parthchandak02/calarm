//
//  NextAlarmBoard.swift
//  Calarm
//

import SwiftUI

/// The schedule's one next-alarm signal: a split-flap countdown to the next ring.
struct NextAlarmBoard: View {
    @Environment(\.calarmTheme) private var theme

    let event: ScheduleEvent?
    let fireDate: Date?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                Text(event == nil ? "NO ALARM SET" : "NEXT ALARM")
                    .font(CalarmFont.boardLabel)
                    .tracking(2)
                    .foregroundStyle(event == nil ? theme.textSecondary : theme.accent)

                if let event, let fireDate {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        FlapCountdown(
                            groups: DepartureBoard.countdownGroups(until: fireDate, now: context.date),
                            isLit: true
                        )
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title)
                            .font(CalarmFont.boardTitle)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Text("Rings \(CalarmTheme.eventTimeString(fireDate)) · starts \(CalarmTheme.eventTimeString(event.startDate))")
                            .font(CalarmFont.boardDetail)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                } else {
                    FlapCountdown(groups: ["--", "--", "--", "--"], isLit: false)
                    Text("Tap a square to arm an event.")
                        .font(CalarmFont.boardDetail)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CalarmTheme.rowPaddingH)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(event == nil)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.surfaceStroke)
                .frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(event == nil ? "" : "Opens the event")
    }

    private var accessibilityText: String {
        guard let event, let fireDate else { return "No alarm set" }
        return "Next alarm: \(event.title), rings at \(CalarmTheme.eventTimeString(fireDate))"
    }
}

/// `DD : HH : MM : SS` as split-flap tiles, with the unit under each pair.
private struct FlapCountdown: View {
    @Environment(\.calarmTheme) private var theme
    @ScaledMetric(relativeTo: .largeTitle) private var tileWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var tileHeight: CGFloat = 52

    let groups: [String]
    let isLit: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Text(":")
                        .font(CalarmFont.countdownSeparator)
                        .foregroundStyle(theme.textSecondary)
                        .frame(height: tileHeight)
                }
                VStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach(Array(group.enumerated()), id: \.offset) { _, character in
                            tile(String(character))
                        }
                    }
                    Text(DepartureBoard.countdownUnits[index])
                        .font(CalarmFont.boardLabel)
                        .tracking(1.5)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    private func tile(_ character: String) -> some View {
        Text(character)
            .font(CalarmFont.countdown)
            .foregroundStyle(isLit ? theme.accent : theme.textSecondary)
            .contentTransition(.numericText(countsDown: true))
            .animation(.snappy, value: character)
            .frame(width: tileWidth, height: tileHeight)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                Rectangle()
                    .fill(theme.background)
                    .frame(height: 1)
            }
    }
}
