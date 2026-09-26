//
//  CalarmApp.swift
//  Calarm
//

import AlarmKit
import SwiftUI
import UIKit

@main
struct CalarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var scheduleStore = ScheduleStore()
    @StateObject private var themeStore = ThemeStore()

    init() {
        if ScreenshotMode.isEnabled {
            ScreenshotDemoData.applyDemoPreferencesSync()
        }
        CalarmPersistence.migrateIfNeeded()
        CalarmTips.configure()
    }

    var body: some Scene {
        WindowGroup {
            CalarmRootView()
                .environmentObject(scheduleStore)
                .environmentObject(themeStore)
                .task {
                    await scheduleStore.bootstrap()
                }
                .onOpenURL { url in
                    scheduleStore.handleIncomingURL(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    Task { await scheduleStore.refreshOnForeground() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    scheduleStore.handleSignificantTimeChange()
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSSystemTimeZoneDidChange)) { _ in
                    Task { await scheduleStore.reload() }
                }
        }
    }
}

/// Injects the resolved theme once at the root so every child reads the same live values.
private struct CalarmRootView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: CalarmTheme {
        themeStore.theme(colorScheme: colorScheme)
    }

    var body: some View {
        ScheduleView()
            .environment(\.calarmTheme, theme)
            .onAppear(perform: applyAppearance)
            .onChange(of: themeStore.appearance) { _, _ in applyAppearance() }
            .onChange(of: themeStore.accent) { _, _ in
                scheduleStore.refreshAfterThemeChange()
            }
            .onChange(of: themeStore.useCalendarColorInLiveActivity) { _, _ in
                scheduleStore.refreshAfterThemeChange()
            }
    }

    // `.preferredColorScheme` does not reach an already-presented sheet when it goes back to
    // nil (System): the sheet kept the last explicit scheme. Overriding the window reaches
    // every presented controller at once.
    private func applyAppearance() {
        let style = themeStore.appearance.userInterfaceStyle
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
