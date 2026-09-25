//
//  FlapTimer.swift
//  CalarmShared
//
//  Split-flap tiles behind the system's self-ticking timer text, for the Live Activity.
//
//  A Live Activity cannot redraw every second, so the digits must come from
//  `Text(timerInterval:)`, which iOS ticks itself. Its format does not zero-pad the leading
//  unit (verified 2026-09-24: 5:07, 45:07, 2:05:00, 14:03:00), so the string gets shorter as
//  it crosses 10:00 or 1:00:00 without the widget re-rendering. Tiles are therefore laid out
//  from the trailing edge with the text trailing-aligned over them: seconds and minutes keep
//  their tiles, and a unit that drops off leaves a blank flap on the left.
//

import SwiftUI
import UIKit

nonisolated enum FlapLayout {
    enum Cell: Equatable {
        case digit
        case colon
    }

    struct Group: Equatable {
        let digits: Int
        let unit: String
    }

    /// Groups for the timer string `Text(timerInterval:, showsHours: remaining >= 3600)` shows
    /// when `remaining` is left.
    static func groups(remaining: TimeInterval) -> [Group] {
        let seconds = max(0, Int(remaining))
        if seconds >= 3_600 {
            return [
                Group(digits: String(seconds / 3_600).count, unit: "HRS"),
                Group(digits: 2, unit: "MIN"),
                Group(digits: 2, unit: "SEC"),
            ]
        }
        return [Group(digits: String(seconds / 60).count, unit: "MIN"), Group(digits: 2, unit: "SEC")]
    }

    static func cells(for groups: [Group]) -> [Cell] {
        groups.enumerated().flatMap { index, group in
            (index > 0 ? [Cell.colon] : []) + Array(repeating: Cell.digit, count: group.digits)
        }
    }
}

struct FlapTimer: View {
    static let fontName = "GeistPixel-Square"

    let fireDate: Date?
    let staticText: String?
    let remaining: TimeInterval
    let fontSize: CGFloat
    let tint: Color
    var showsUnits = false

    /// Ticks to `fireDate`.
    init(fireDate: Date, fontSize: CGFloat, tint: Color, showsUnits: Bool = false) {
        self.fireDate = fireDate
        staticText = nil
        remaining = fireDate.timeIntervalSinceNow
        self.fontSize = fontSize
        self.tint = tint
        self.showsUnits = showsUnits
    }

    /// A frozen value, for a paused countdown.
    init(text: String, remaining: TimeInterval, fontSize: CGFloat, tint: Color, showsUnits: Bool = false) {
        fireDate = nil
        staticText = text
        self.remaining = remaining
        self.fontSize = fontSize
        self.tint = tint
        self.showsUnits = showsUnits
    }

    private var groups: [FlapLayout.Group] { FlapLayout.groups(remaining: remaining) }

    private var uiFont: UIFont {
        UIFont(name: Self.fontName, size: fontSize) ?? .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// Space after every glyph, so a tile is wider than the digit it holds.
    private var tracking: CGFloat { round(fontSize * 0.22) }

    /// Cell widths match the text's own advances exactly, or the tiles drift under it.
    private var digitWidth: CGFloat {
        ("0" as NSString).size(withAttributes: [.font: uiFont, .kern: tracking]).width
    }

    private var colonWidth: CGFloat {
        (":" as NSString).size(withAttributes: [.font: uiFont, .kern: tracking]).width
    }

    private var tileHeight: CGFloat { ceil(fontSize * 1.4) }

    private var boardWidth: CGFloat {
        FlapLayout.cells(for: groups).reduce(0) { $0 + ($1 == .digit ? digitWidth : colonWidth) }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            ZStack(alignment: .trailing) {
                HStack(spacing: 0) {
                    ForEach(Array(FlapLayout.cells(for: groups).enumerated()), id: \.offset) { _, cell in
                        switch cell {
                        case .digit: tile
                        case .colon: Color.clear.frame(width: colonWidth, height: tileHeight)
                        }
                    }
                }
                timerText
                    // Not `Font(uiFont)`: a UIFont-backed Font blanked the whole Live
                    // Activity on device (build 2129) while `.custom` renders.
                    .font(.custom(Self.fontName, fixedSize: fontSize))
                    .tracking(tracking)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                    // Never `.fixedSize()`: timer text reserves the width of the longest
                    // value it could show, and the compact Island stretches to fit it.
                    .frame(width: boardWidth, alignment: .trailing)
                    .offset(x: -tracking / 2)
            }
            .frame(width: boardWidth, height: tileHeight, alignment: .trailing)

            if showsUnits {
                HStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        if index > 0 {
                            Color.clear.frame(width: colonWidth, height: 1)
                        }
                        Text(group.unit)
                            .font(.custom(Self.fontName, fixedSize: max(8, fontSize * 0.3)))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                            .fixedSize()
                            .frame(width: digitWidth * CGFloat(group.digits))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var timerText: some View {
        if let fireDate {
            Text(timerInterval: Date.now...fireDate, countsDown: true, showsHours: remaining >= 3_600)
        } else {
            Text(staticText ?? "")
        }
    }

    /// Still, so it has to read as mechanical without motion: a lighter upper flap, a
    /// darker lower one, a hinge gap and a drop shadow. iOS ticks the digits itself, so a
    /// per-second flip cannot be drawn here.
    private var tile: some View {
        VStack(spacing: 0) {
            Color.white.opacity(0.13)
            Color.white.opacity(0.07)
        }
        .clipShape(RoundedRectangle(cornerRadius: max(2, fontSize * 0.14), style: .continuous))
        .overlay {
            Rectangle()
                .fill(Color.black.opacity(0.85))
                .frame(height: max(1, fontSize * 0.05))
        }
        .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
        .padding(.horizontal, 1)
        .frame(width: digitWidth, height: tileHeight)
    }
}
