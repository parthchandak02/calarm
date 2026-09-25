//
//  CalarmFont.swift
//  Calarm
//

import SwiftUI

enum CalarmFont {
    private static let pixel = "GeistPixel-Square"

    /// App wordmark — Geist Pixel has one weight; size gives the bold presence.
    static let appTitle = Font.custom(pixel, size: 34, relativeTo: .largeTitle)
    /// Inline nav-bar wordmark — always visible, top-leading.
    static let navBarWordmark = Font.custom(pixel, size: 28, relativeTo: .title2)

    static let largeTitle = Font.custom(pixel, size: 34, relativeTo: .largeTitle)
    static let title = Font.custom(pixel, size: 28, relativeTo: .title)
    static let title2 = Font.custom(pixel, size: 22, relativeTo: .title2)
    static let title3 = Font.custom(pixel, size: 20, relativeTo: .title3)
    static let headline = Font.custom(pixel, size: 17, relativeTo: .headline)
    static let body = Font.custom(pixel, size: 17, relativeTo: .body)
    static let bodyMedium = Font.custom(pixel, size: 17, relativeTo: .body)
    static let callout = Font.custom(pixel, size: 16, relativeTo: .callout)
    static let subheadline = Font.custom(pixel, size: 15, relativeTo: .subheadline)
    static let subheadlineSemibold = Font.custom(pixel, size: 15, relativeTo: .subheadline)
    static let footnote = Font.custom(pixel, size: 13, relativeTo: .footnote)
    static let caption = Font.custom(pixel, size: 12, relativeTo: .caption)
    static let captionSemibold = Font.custom(pixel, size: 12, relativeTo: .caption)
    static let sectionHeader = Font.custom(pixel, size: 14, relativeTo: .footnote)
    static let time = Font.custom(pixel, size: 15, relativeTo: .subheadline).monospacedDigit()

    /// Departure-board schedule: pixel type only for what ticks, mono for titles so long
    /// event names stay readable.
    static let countdown = Font.custom(pixel, size: 40, relativeTo: .largeTitle).monospacedDigit()
    static let countdownSeparator = Font.custom(pixel, size: 32, relativeTo: .largeTitle)
    static let boardLabel = Font.custom(pixel, size: 11, relativeTo: .caption2)
    static let boardTitle = Font.system(.subheadline, design: .monospaced, weight: .medium)
    static let boardDetail = Font.system(.caption, design: .monospaced)
    static let dayHeader = Font.custom(pixel, size: 17, relativeTo: .headline)
    static let boardTitleBar = Font.custom(pixel, size: 13, relativeTo: .headline)
    static let flapTile = Font.custom(pixel, size: 15, relativeTo: .body).monospacedDigit()
}
