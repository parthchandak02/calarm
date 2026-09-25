//
//  FlipTile.swift
//  Calarm
//

import SwiftUI

/// One split-flap character. On a change the old top half falls forward on the midline
/// hinge and the new bottom half lands under it, darkening as each turns edge-on.
/// Tuned by the owner in `notes/ui-redesign/flip.html`: 500 ms, strong perspective, settle.
struct FlipTile: View {
    @Environment(\.calarmTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let character: String
    let font: Font
    let color: Color
    let width: CGFloat
    let height: CGFloat

    static let duration: Double = 0.5
    static let perspective: CGFloat = 0.42

    @State private var top = ""
    @State private var bottom = ""
    @State private var fallingTop = ""
    @State private var landingBottom = ""
    @State private var fallAngle: Double = 0
    @State private var landAngle: Double = 90
    @State private var generation = 0

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                half(top, isTop: true)
                    .modifier(FlapShade(angle: fallAngle + 90, maxShade: 0.35))
                half(bottom, isTop: false)
            }
            VStack(spacing: 0) {
                half(fallingTop, isTop: true)
                    .modifier(FlapTurn(angle: fallAngle, anchor: .bottom))
                Color.clear.frame(height: height / 2)
            }
            VStack(spacing: 0) {
                Color.clear.frame(height: height / 2)
                half(landingBottom, isTop: false)
                    .modifier(FlapTurn(angle: landAngle, anchor: .top))
            }
            Rectangle()
                .fill(theme.background)
                .frame(height: 1)
        }
        .frame(width: width, height: height)
        .compositingGroup()
        .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.12), radius: 3, y: 2)
        .onAppear { settle(on: character) }
        .onChange(of: character) { old, new in flip(from: old, to: new) }
    }

    private func settle(on value: String) {
        top = value
        bottom = value
        fallingTop = value
        landingBottom = value
        fallAngle = 0
        landAngle = 90
    }

    private func flip(from old: String, to new: String) {
        generation += 1
        let current = generation
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            settle(on: old)
            top = new
            landingBottom = new
        }
        guard !reduceMotion else {
            withTransaction(reset) { settle(on: new) }
            return
        }
        withAnimation(.easeIn(duration: Self.duration / 2)) {
            fallAngle = -90
        } completion: {
            guard current == generation else { return }
            withAnimation(.spring(duration: Self.duration / 2, bounce: 0.35)) {
                landAngle = 0
            } completion: {
                guard current == generation else { return }
                withTransaction(reset) { settle(on: new) }
            }
        }
    }

    // Opaque layers: `theme.surface` is translucent, and a flap drawn over a static half
    // would otherwise double its tint mid-flip.
    private func half(_ value: String, isTop: Bool) -> some View {
        let radius: CGFloat = 6
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: isTop ? radius : 0,
            bottomLeadingRadius: isTop ? 0 : radius,
            bottomTrailingRadius: isTop ? 0 : radius,
            topTrailingRadius: isTop ? radius : 0,
            style: .continuous
        )
        return ZStack {
            theme.background
            theme.surface
            if !isTop {
                Color.black.opacity(theme.isDark ? 0.18 : 0.04)
            }
            Text(value)
                .font(font)
                .foregroundStyle(color)
                .frame(width: width, height: height)
                .frame(width: width, height: height / 2, alignment: isTop ? .top : .bottom)
        }
        .frame(width: width, height: height / 2)
        .clipShape(shape)
    }
}

/// Rotates a flap about its hinge and darkens it as it turns edge-on. Animatable so the
/// shade follows the angle frame by frame instead of jumping to its end value.
private struct FlapTurn: ViewModifier, Animatable {
    var angle: Double
    let anchor: UnitPoint

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .overlay(Color.black.opacity(min(1, abs(angle) / 90) * 0.55))
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 1, y: 0, z: 0),
                anchor: anchor,
                perspective: FlipTile.perspective
            )
            .opacity(abs(angle) >= 89.5 ? 0 : 1)
    }
}

/// Shades the static top half while the flap in front of it is still covering it.
private struct FlapShade: ViewModifier, Animatable {
    var angle: Double
    let maxShade: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content.overlay(Color.black.opacity(max(0, min(1, angle / 90)) * maxShade))
    }
}
