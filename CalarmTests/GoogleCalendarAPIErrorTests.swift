//
//  GoogleCalendarAPIErrorTests.swift
//  CalarmTests
//

import XCTest
@testable import Calarm

final class GoogleCalendarAPIErrorTests: XCTestCase {
    func testNotConfiguredMessage() {
        let error = GoogleCalendarAPIError.notConfigured
        XCTAssertEqual(
            error.errorDescription,
            "Google Calendar is not configured. Add GoogleService-Info.plist."
        )
    }

    func testNotSignedInMessage() {
        let error = GoogleCalendarAPIError.notSignedIn
        XCTAssertEqual(error.errorDescription, "Sign in to Google Calendar first.")
    }

    func testInvalidResponseMessage() {
        let error = GoogleCalendarAPIError.invalidResponse
        XCTAssertEqual(error.errorDescription, "Unexpected response from Google Calendar.")
    }

    func testSyncTokenExpiredMessage() {
        let error = GoogleCalendarAPIError.syncTokenExpired
        XCTAssertEqual(error.errorDescription, "Google Calendar sync token expired.")
    }

    func testHTTPErrorUsesSanitizedMessage() {
        let body = "{\"error\":{\"message\":\"Rate Limit Exceeded\"}}"
        let error = GoogleCalendarAPIError.http(status: 429, message: body)
        XCTAssertEqual(
            error.errorDescription,
            "Too many requests to Google Calendar. Try again later."
        )
        XCTAssertFalse(error.errorDescription?.contains(body) ?? true)
    }

    func testHTTP401UsesSignInAgainMessage() {
        let error = GoogleCalendarAPIError.http(status: 401, message: "raw body")
        XCTAssertEqual(error.errorDescription, "Your Google sign-in expired. Sign in again.")
    }

    func testLocalizedDescriptionMatchesErrorDescription() {
        let errors: [GoogleCalendarAPIError] = [
            .notConfigured,
            .notSignedIn,
            .invalidResponse,
            .syncTokenExpired,
            .http(status: 500, message: "Server error"),
        ]

        for error in errors {
            XCTAssertEqual(error.localizedDescription, error.errorDescription)
        }
    }
}
