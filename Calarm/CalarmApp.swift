//
//  CalarmApp.swift
//  Calarm
//

import AlarmKit
import SwiftUI

@main
struct CalarmApp: App {
    @StateObject private var scheduleStore = ScheduleStore()
    @StateObject private var themeStore = ThemeStore()

    init() {
        if ScreenshotMode.isEnabled {
            ScreenshotDemoData.applyDemoPreferencesSync()
        }
        CalarmPersistence.migrateIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            CalarmRootView()
                .environmentObject(scheduleStore)
                .environmentObject(themeStore)
                .task {
                    await scheduleStore.bootstrap()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    Task { await scheduleStore.refreshOnForeground() }
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
            .preferredColorScheme(themeStore.appearance.preferredColorScheme)
    }
}
