import Foundation
import MapKit
import UIKit
import UserNotifications

// MARK: - Audio-guide scripts

/// Builds the two-minute script: Wikipedia text, rewritten by Claude for the ear when a key is set,
/// otherwise the start of the article trimmed to two minutes.
struct GuideService {
    var anthropicKey: String
    var model: String
    var lang: String

    func script(for place: Place, city: String?) async throws -> String {
        let source = await sourceText(for: place)
        if !anthropicKey.isEmpty {
            let req = Claude.request(model: model, key: anthropicKey, system: Guide.system,
                                     user: Guide.prompt(place: place, source: source, city: city), maxTokens: 900)
            let text = try Claude.parseText(await Net.data(req))
            return Guide.tidy(text)
        }
        if let s = source, !s.isEmpty { return Guide.trim(s) }
        throw SourceError.missingKey("Anthropic key (no Wikipedia article was found for this place)")
    }

    private func sourceText(for place: Place) async -> String? {
        let lang = place.wikipediaLang ?? self.lang
        if let t = place.wikipediaTitle, let d = try? await Net.data(Wikipedia.extractURL(title: t, lang: lang)) {
            return Wikipedia.parseExtract(d)
        }
        // Saved places rarely carry a Wikipedia link: look one up by name and keep it only if it is near.
        guard let c = place.coordinate,
              let near = try? await Net.data(Wikipedia.nearbyURL(c, lang: lang, radius: 400, limit: 20)) else { return nil }
        let pages = Wikipedia.parseNearby(near)
        guard let match = pages.first(where: { Ranker.sameName($0.title, place.name) }),
              let d = try? await Net.data(Wikipedia.extractURL(title: match.title, lang: lang)) else { return nil }
        return Wikipedia.parseExtract(d)
    }
}

// MARK: - Notifications

enum Notifier {
    static let category = "roam.place"
    static let listen = "roam.listen"
    static let navigate = "roam.navigate"
    static let mute = "roam.mute"

    static func register() {
        let listenA = UNNotificationAction(identifier: listen, title: "Listen (2 min)", options: [.foreground],
                                           icon: UNNotificationActionIcon(systemImageName: "headphones"))
        let navA = UNNotificationAction(identifier: navigate, title: "Walk there", options: [.foreground],
                                        icon: UNNotificationActionIcon(systemImageName: "figure.walk"))
        let muteA = UNNotificationAction(identifier: mute, title: "Don't remind me", options: [.destructive],
                                         icon: UNNotificationActionIcon(systemImageName: "bell.slash"))
        let cat = UNNotificationCategory(identifier: category, actions: [listenA, navA, muteA], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func post(_ text: AlertText, placeID: String) {
        let c = UNMutableNotificationContent()
        c.title = text.title
        c.body = text.body
        c.sound = .default
        c.categoryIdentifier = category
        c.threadIdentifier = "roam.nearby"
        c.userInfo = ["placeID": placeID]
        c.interruptionLevel = .active
        c.relevanceScore = 0.8
        let req = UNNotificationRequest(identifier: "roam.\(placeID)", content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - Turn-by-turn handoff

enum Navigator {
    static func walk(to c: Coordinate, name: String, using app: NavApp) {
        if app == .google {
            let g = URL(string: "comgooglemaps://?daddr=\(c.lat),\(c.lng)&directionsmode=walking")!
            if UIApplication.shared.canOpenURL(g) {
                UIApplication.shared.open(g)
                return
            }
            let web = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(c.lat),\(c.lng)&travelmode=walking")!
            UIApplication.shared.open(web)
            return
        }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c.cl))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    static func open(_ urlString: String?) {
        guard let s = urlString, let u = URL(string: s) else { return }
        UIApplication.shared.open(u)
    }
}

// MARK: - City name for the status line and the guide prompt

enum Geocode {
    static func city(_ c: Coordinate) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.lat, longitude: c.lng))
        guard let m = marks?.first else { return nil }
        return m.locality ?? m.subAdministrativeArea ?? m.administrativeArea
    }

    static func forward(_ text: String) async -> (Coordinate, String?)? {
        let marks = try? await CLGeocoder().geocodeAddressString(text)
        guard let m = marks?.first, let l = m.location else { return nil }
        return (l.coord, m.locality ?? m.administrativeArea)
    }
}
