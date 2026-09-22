//
//  AppDelegate.swift
//  Calarm
//

import GoogleSignIn
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Must happen here. BGTaskScheduler requires every launch handler to be
        // registered before this method returns; registering from a SwiftUI `.task`
        // is too late and installs nothing. See MorningSyncScheduler.
        MorningSyncScheduler.registerHandlers()
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
