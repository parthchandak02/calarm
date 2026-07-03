//
//  CalarmNavigationStyle.swift
//  Calarm
//

import SwiftUI
import UIKit

/// Applies navigation bar styling to the hosting `UINavigationController` only.
/// Avoids `UINavigationBar.appearance()`, which causes stale / inverted chrome when themes change.
struct CalarmNavigationStyle: ViewModifier {
    let theme: CalarmTheme
    var prefersLargeTitles: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                NavigationBarThemeBridge(
                    theme: theme,
                    prefersLargeTitles: prefersLargeTitles
                )
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
    }
}

private struct NavigationBarThemeBridge: UIViewControllerRepresentable {
    let theme: CalarmTheme
    let prefersLargeTitles: Bool

    func makeUIViewController(context: Context) -> BridgeViewController {
        BridgeViewController()
    }

    func updateUIViewController(_ viewController: BridgeViewController, context: Context) {
        viewController.apply(theme: theme, prefersLargeTitles: prefersLargeTitles)
    }

    final class BridgeViewController: UIViewController {
        private var theme: CalarmTheme?
        private var prefersLargeTitles = false
        private var appliedSignature: String?

        func apply(theme: CalarmTheme, prefersLargeTitles: Bool) {
            self.theme = theme
            self.prefersLargeTitles = prefersLargeTitles
            refreshNavigationBar()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            refreshNavigationBar()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            refreshNavigationBar()
        }

        private func refreshNavigationBar() {
            guard let theme else { return }
            guard let navigationBar = navigationController?.navigationBar else { return }

            let signature = "\(theme.isDark)-\(theme.accent.description)-\(prefersLargeTitles)"
            guard appliedSignature != signature else { return }
            appliedSignature = signature

            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(theme.background)
            appearance.shadowColor = .clear

            let largeFont = UIFont(name: "GeistPixel-Square", size: 34) ?? .boldSystemFont(ofSize: 34)
            let inlineFont = UIFont(name: "GeistPixel-Square", size: 17) ?? .boldSystemFont(ofSize: 17)

            appearance.largeTitleTextAttributes = [
                .font: largeFont,
                .foregroundColor: UIColor(theme.textPrimary)
            ]
            appearance.titleTextAttributes = [
                .font: inlineFont,
                .foregroundColor: UIColor(theme.textPrimary)
            ]

            navigationBar.prefersLargeTitles = prefersLargeTitles
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.compactAppearance = appearance
            navigationBar.compactScrollEdgeAppearance = appearance
            navigationBar.tintColor = UIColor(theme.accent)
        }
    }
}

extension View {
    func calarmNavigationStyle(
        theme: CalarmTheme,
        prefersLargeTitles: Bool = false
    ) -> some View {
        modifier(CalarmNavigationStyle(theme: theme, prefersLargeTitles: prefersLargeTitles))
    }

    func calarmToolbarChrome(theme: CalarmTheme) -> some View {
        toolbarColorScheme(theme.toolbarColorScheme, for: .navigationBar)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
