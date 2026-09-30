//
//  NextAlarmBoard.swift
//  Calarm
//

import SwiftUI

/// The schedule's one next-alarm signal: a split-flap countdown to the next ring. The event
/// itself is not repeated here (owner feedback 2026-09-26): it is in the list below, and
/// tapping the board opens it.
struct NextAlarmBoard: View {
    @Environment(\.calarmTheme) private var theme

    let rings: [DepartureBoard.Ring]
    let onOpen: (String) -> Void

    var body: some View {
        // Measured against the clock, not `context.date`: SwiftUI re-renders the content with
        // its last entry's date when the store publishes, and after a stretch in the
        // background that date can be hours old.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = Date()
            board(next: DepartureBoard.nextRing(rings, now: now), now: now)
        }
    }

    private func board(next: DepartureBoard.Ring?, now: Date) -> some View {
        Button { if let next { onOpen(next.eventID) } } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(next == nil ? "NO ALARM SET" : "NEXT ALARM")
                    .font(CalarmFont.boardLabel)
                    .tracking(2)
                    .foregroundStyle(next == nil ? theme.textSecondary : theme.accent)

                if let next {
                    FlapCountdown(
                        groups: DepartureBoard.countdownGroups(until: next.fireDate, now: now),
                        isLit: true
                    )
                } else {
                    FlapCountdown(groups: ["--", "--", "--", "--"], isLit: false)
                    Text("Tap a square to arm an event.")
                        .font(CalarmFont.boardDetail)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CalarmTheme.rowPaddingH)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(next == nil)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(next.map { "Next alarm: \($0.title), rings at \(CalarmTheme.eventTimeString($0.fireDate))" } ?? "No alarm set")
        .accessibilityHint(next == nil ? "" : "Opens the event")
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
        FlipTile(
            character: character,
            font: CalarmFont.countdown,
            color: isLit ? theme.accent : theme.textSecondary,
            width: tileWidth,
            height: tileHeight
        )
    }
}
