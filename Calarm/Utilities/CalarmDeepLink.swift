//
//  CalarmDeepLink.swift
//  Calarm
//

import Foundation

enum CalarmDeepLink {
    static let scheme = "calarm"
    static let eventHost = "event"
    static let eventIDQueryItem = "id"

    static func eventURL(eventID: String) -> URL? {
        guard !eventID.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = eventHost
        components.queryItems = [URLQueryItem(name: eventIDQueryItem, value: eventID)]
        return components.url
    }

    static func eventID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == eventHost else {
            return nil
        }

        if let queryID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == eventIDQueryItem })?
            .value,
           !queryID.isEmpty {
            return queryID
        }

        let pathID = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return pathID.isEmpty ? nil : pathID
    }
}
