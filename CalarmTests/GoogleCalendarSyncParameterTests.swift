//
//  GoogleCalendarSyncParameterTests.swift
//  CalarmTests
//

import XCTest
@testable import Calarm

/// Guards the `syncToken` contract, which is the part of the Google path that was wrong
/// for a year in a way no test could see.
///
/// Google forbids `iCalUID`, `orderBy`, `privateExtendedProperty`, `q`,
/// `sharedExtendedProperty`, `timeMin`, `timeMax` and `updatedMin` on any request
/// carrying a `syncToken`, and requires every *other* parameter to match the request that
/// minted the token. The old code minted its token from a bounded, ordered query, so the
/// parameter set was structurally impossible to match, and the resulting deltas were
/// undefined rather than wrong-and-noisy.
///
/// `GoogleCalendarAPIClient` takes an injectable `URLSession`. That seam existed from the
/// start and nothing used it.
/// `@MainActor` because this target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
/// which isolates the API client's response types to the main actor. Reading
/// `GoogleCalendarEventsPage.nextSyncToken` from a nonisolated test body is a warning
/// today and an error under the Swift 6 language mode.
@MainActor
final class GoogleCalendarSyncParameterTests: XCTestCase {
    private var client: GoogleCalendarAPIClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        client = GoogleCalendarAPIClient(session: URLSession(configuration: configuration))
    }

    override func tearDown() {
        StubURLProtocol.reset()
        client = nil
        super.tearDown()
    }

    /// Parameters forbidden alongside a sync token, per the Events: list reference.
    private static let forbiddenWithSyncToken = [
        "iCalUID", "orderBy", "privateExtendedProperty",
        "q", "sharedExtendedProperty", "timeMin", "timeMax", "updatedMin"
    ]

    // MARK: - The token-minting request

    func testFullSyncOmitsEveryParameterTheIncrementalCannotCarry() async throws {
        StubURLProtocol.respond(json: #"{"items":[],"nextSyncToken":"tok-1"}"#)

        _ = try await client.listFullSyncEvents(
            calendarID: "primary",
            accessToken: "at",
            timeMin: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let query = try XCTUnwrap(StubURLProtocol.requests.last?.queryPairs)
        // timeMin is the one exception: allowed on the full sync, and it does not
        // suppress the token. Google's own sync guide sample passes it.
        XCTAssertNotNil(query["timeMin"])
        for parameter in Self.forbiddenWithSyncToken where parameter != "timeMin" {
            XCTAssertNil(query[parameter], "\(parameter) must not appear on the token-minting request")
        }
    }

    func testFullSyncDoesNotExpandRecurrences() async throws {
        StubURLProtocol.respond(json: #"{"items":[],"nextSyncToken":"tok-1"}"#)

        _ = try await client.listFullSyncEvents(
            calendarID: "primary",
            accessToken: "at",
            timeMin: Date()
        )

        let query = try XCTUnwrap(StubURLProtocol.requests.last?.queryPairs)
        // With singleEvents=true and no timeMax, Google expands every recurrence for all
        // time. One daily standup would be thousands of rows.
        XCTAssertEqual(query["singleEvents"], "false")
        XCTAssertEqual(query["showDeleted"], "true")
    }

    // MARK: - The incremental request

    func testIncrementalCarriesTokenAndNothingForbidden() async throws {
        StubURLProtocol.respond(json: #"{"items":[],"nextSyncToken":"tok-2"}"#)

        _ = try await client.listIncrementalEvents(
            calendarID: "primary",
            accessToken: "at",
            syncToken: "tok-1"
        )

        let query = try XCTUnwrap(StubURLProtocol.requests.last?.queryPairs)
        XCTAssertEqual(query["syncToken"], "tok-1")
        for parameter in Self.forbiddenWithSyncToken {
            XCTAssertNil(query[parameter], "\(parameter) is forbidden alongside syncToken")
        }
    }

    /// The mismatch that made the old deltas undefined. These two requests must agree on
    /// every parameter that is not `timeMin` or `syncToken`.
    func testIncrementalParametersMatchTheFullSync() async throws {
        StubURLProtocol.respond(json: #"{"items":[],"nextSyncToken":"tok-1"}"#)
        _ = try await client.listFullSyncEvents(calendarID: "primary", accessToken: "at", timeMin: Date())
        var full = try XCTUnwrap(StubURLProtocol.requests.last?.queryPairs)

        StubURLProtocol.respond(json: #"{"items":[],"nextSyncToken":"tok-2"}"#)
        _ = try await client.listIncrementalEvents(calendarID: "primary", accessToken: "at", syncToken: "tok-1")
        var incremental = try XCTUnwrap(StubURLProtocol.requests.last?.queryPairs)

        full.removeValue(forKey: "timeMin")
        incremental.removeValue(forKey: "syncToken")
        XCTAssertEqual(full, incremental)
    }

    // MARK: - Failure and pagination

    func testExpiredTokenSurfacesAsSyncTokenExpired() async {
        StubURLProtocol.respond(json: #"{"error":"gone"}"#, status: 410)

        do {
            _ = try await client.listIncrementalEvents(
                calendarID: "primary",
                accessToken: "at",
                syncToken: "stale"
            )
            XCTFail("410 must not be reported as success")
        } catch GoogleCalendarAPIError.syncTokenExpired {
            // Expected. This is what tells the service to clear and full sync.
        } catch {
            XCTFail("expected syncTokenExpired, got \(error)")
        }
    }

    /// `nextSyncToken` appears only on the final page, so a paginated sync that stops
    /// early silently never obtains one.
    func testTokenIsTakenFromTheLastPage() async throws {
        StubURLProtocol.respondInSequence([
            #"{"items":[],"nextPageToken":"p2"}"#,
            #"{"items":[],"nextSyncToken":"final-token"}"#
        ])

        let page = try await client.listFullSyncEvents(
            calendarID: "primary",
            accessToken: "at",
            timeMin: Date()
        )

        XCTAssertEqual(page.nextSyncToken, "final-token")
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertEqual(StubURLProtocol.requests.last?.queryPairs["pageToken"], "p2")
    }

    func testAccessTokenIsSentAsBearer() async throws {
        StubURLProtocol.respond(json: #"{"items":[]}"#)

        _ = try await client.listIncrementalEvents(
            calendarID: "primary",
            accessToken: "secret-token",
            syncToken: "tok"
        )

        let header = StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(header, "Bearer secret-token")
    }

    /// Calendar IDs are email-shaped and must survive being placed in a path exactly
    /// once.
    ///
    /// This caught a live bug. `get()` assigned to `URLComponents.path`, whose setter
    /// escapes `%`, so a caller-encoded `team%20room` was sent as `team%2520room` and
    /// Google was asked for a calendar that does not exist. Fixed by assigning to
    /// `percentEncodedPath`.
    func testCalendarIDIsEncodedExactlyOnce() async throws {
        StubURLProtocol.respond(json: #"{"items":[]}"#)

        _ = try await client.listIncrementalEvents(
            calendarID: "team room@group.calendar.google.com",
            accessToken: "at",
            syncToken: "tok"
        )

        let url = try XCTUnwrap(StubURLProtocol.requests.last?.url?.absoluteString)
        XCTAssertTrue(url.contains("team%20room@group.calendar.google.com"), "got: \(url)")
        XCTAssertFalse(url.contains("%2520"), "double encoded: \(url)")
        XCTAssertFalse(url.contains("team room"), "a raw space is not a valid URL")
    }

    /// Every Google holiday calendar contains a `#`, which is the character most likely
    /// to be mangled and the one that silently breaks a real subscription.
    func testHolidayCalendarIDSurvivesEncoding() async throws {
        StubURLProtocol.respond(json: #"{"items":[]}"#)

        _ = try await client.listIncrementalEvents(
            calendarID: "en.usa#holiday@group.v.calendar.google.com",
            accessToken: "at",
            syncToken: "tok"
        )

        let url = try XCTUnwrap(StubURLProtocol.requests.last?.url?.absoluteString)
        XCTAssertTrue(url.contains("en.usa%23holiday@group.v.calendar.google.com"), "got: \(url)")
        XCTAssertFalse(url.contains("%2523"), "double encoded: \(url)")
        // A bare `#` would truncate the path into a fragment and silently request the
        // wrong calendar with a 200 response.
        XCTAssertNil(StubURLProtocol.requests.last?.url?.fragment)
    }
}

// MARK: - Stub transport

private extension URLRequest {
    var queryPairs: [String: String] {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        return Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var bodies: [String] = []
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var index = 0
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() {
        bodies = []
        status = 200
        index = 0
        requests = []
    }

    static func respond(json: String, status code: Int = 200) {
        bodies = [json]
        status = code
        index = 0
        requests = []
    }

    static func respondInSequence(_ jsonBodies: [String]) {
        bodies = jsonBodies
        status = 200
        index = 0
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let body = Self.bodies.isEmpty
            ? "{}"
            : Self.bodies[min(Self.index, Self.bodies.count - 1)]
        Self.index += 1

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
