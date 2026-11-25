import AuthenticationServices
import Security
import CryptoKit
import EventKit
import Foundation
import UIKit

// MARK: - Google sign-in (personal account) and Drive

/// Installed-app OAuth with PKCE through the system browser sheet. The refresh token stays in the Keychain;
/// access tokens are kept in memory only.
@MainActor
final class GoogleAccount: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAccount()

    private var accessToken: String?
    private var expiry = Date.distantPast
    private var session: ASWebAuthenticationSession?

    var isSignedIn: Bool { !Keychain.read(.googleRefreshToken).isEmpty }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    func signIn(clientID: String) async throws {
        let id = clientID.trimmingCharacters(in: .whitespaces)
        guard id.hasSuffix(".apps.googleusercontent.com") else {
            throw SourceError.api("Paste the iOS OAuth client ID from Google Cloud (it ends in .apps.googleusercontent.com).")
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = GoogleOAuth.base64url(Data(bytes))
        let challenge = GoogleOAuth.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let url = GoogleOAuth.authURL(clientID: id, challenge: challenge)
        let scheme = GoogleOAuth.redirectScheme(clientID: id)

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
                if let url = url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? SourceError.api("Sign-in was cancelled")) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            s.start()
        }
        guard let code = GoogleOAuth.code(fromCallback: callback) else { throw SourceError.api("Google did not return a code") }
        let tokens = try GoogleOAuth.parseTokens(await Net.data(GoogleOAuth.tokenRequest([
            "code": code, "client_id": id, "redirect_uri": GoogleOAuth.redirectURI(clientID: id),
            "grant_type": "authorization_code", "code_verifier": verifier
        ])))
        if let r = tokens.refresh { Keychain.write(.googleRefreshToken, r) }
        accessToken = tokens.access
        expiry = Date().addingTimeInterval(tokens.expiresIn - 60)
    }

    func signOut() {
        Keychain.write(.googleRefreshToken, "")
        accessToken = nil
        expiry = .distantPast
    }

    func token(clientID: String) async throws -> String {
        if let t = accessToken, Date() < expiry { return t }
        let refresh = Keychain.read(.googleRefreshToken)
        guard !refresh.isEmpty else { throw SourceError.api("Sign in to Google in Settings to search your docs.") }
        let tokens = try GoogleOAuth.parseTokens(await Net.data(GoogleOAuth.tokenRequest([
            "client_id": clientID.trimmingCharacters(in: .whitespaces), "refresh_token": refresh, "grant_type": "refresh_token"
        ])))
        accessToken = tokens.access
        expiry = Date().addingTimeInterval(tokens.expiresIn - 60)
        return tokens.access
    }

    private func authed(_ url: URL, clientID: String) async throws -> Data {
        var r = URLRequest(url: url)
        let first = try await token(clientID: clientID)
        r.setValue("Bearer \(first)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await Net.session.data(for: r)
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            accessToken = nil
            let second = try await token(clientID: clientID)
            r.setValue("Bearer \(second)", forHTTPHeaderField: "Authorization")
            let (retry, _) = try await Net.session.data(for: r)
            return retry
        }
        return data
    }

    func searchDocs(_ text: String, clientID: String) async throws -> [DriveFile] {
        try Drive.parseFiles(await authed(Drive.searchURL(text), clientID: clientID))
    }

    func docText(_ id: String, clientID: String) async throws -> String {
        let data = try await authed(Drive.exportURL(fileID: id), clientID: clientID)
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Calendar (whatever calendars are on the phone, including a synced Google calendar)

enum CalendarService {
    static let store = EKEventStore()

    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Events in the next `days` with a location, geocoded (cached by location text).
    static func upcomingEvents(days: Int = 60) async -> [TripEvent] {
        guard hasAccess else { return [] }
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-86_400)
        let end = Date().addingTimeInterval(Double(days) * 86_400)
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        var out: [TripEvent] = []
        var cache: [String: (Coordinate, String?)] = [:]
        var lookups = 0
        for e in events where !(e.location ?? "").isEmpty {
            let loc = e.location ?? ""
            var coord: Coordinate?
            var city: String?
            if let g = e.structuredLocation?.geoLocation {
                coord = g.coord
            }
            if let hit = cache[loc] {
                coord = coord ?? hit.0
                city = hit.1
            } else if lookups < 25 {
                // CLGeocoder is rate limited; 25 lookups covers two months of travel.
                lookups += 1
                if coord == nil, let f = await Geocode.forward(loc) {
                    coord = f.0
                    city = f.1
                } else if let c = coord {
                    city = await Geocode.city(c)
                }
                if let c = coord { cache[loc] = (c, city) }
            }
            out.append(TripEvent(title: e.title ?? "Event", start: e.startDate, end: e.endDate, location: loc, coordinate: coord, city: city))
        }
        return out
    }
}
