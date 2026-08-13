//
//  GoogleAuthManager.swift
//  Calarm
//

import Combine
import Foundation
import GoogleSignIn
import UIKit

@MainActor
final class GoogleAuthManager: ObservableObject {
    @Published private(set) var isConfigured = false
    @Published private(set) var isSignedIn = false
    @Published private(set) var userEmail: String?
    @Published private(set) var lastError: String?

    func configure() {
        guard let clientID = GoogleOAuthConfig.clientID else {
            isConfigured = false
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        isConfigured = true
        restorePreviousSignIn()
    }

    func restorePreviousSignIn() {
        guard isConfigured else { return }
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            Task { @MainActor in
                if let user {
                    self?.apply(user: user)
                } else {
                    self?.isSignedIn = false
                    self?.userEmail = nil
                    if let error {
                        self?.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    func signIn(presenting viewController: UIViewController) async throws {
        guard isConfigured else { throw GoogleCalendarAPIError.notConfigured }
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController,
            hint: nil,
            additionalScopes: [GoogleOAuthConfig.calendarReadonlyScope]
        )
        apply(user: result.user)
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        userEmail = nil
    }

    func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleCalendarAPIError.notSignedIn
        }
        let refreshed = try await user.refreshTokensIfNeeded()
        let token = refreshed.accessToken.tokenString
        guard !token.isEmpty else {
            throw GoogleCalendarAPIError.notSignedIn
        }
        return token
    }

    private func apply(user: GIDGoogleUser) {
        isSignedIn = true
        userEmail = user.profile?.email
        lastError = nil
    }
}
