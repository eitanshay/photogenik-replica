import Foundation
import Observation

enum NavApp: String, CaseIterable, Identifiable {
    case apple, google
    var id: String { rawValue }
    var label: String { self == .apple ? "Apple Maps" : "Google Maps" }
}

enum TripModeSetting: String, CaseIterable, Identifiable {
    case auto, on, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto (50 km from home)"
        case .on: return "Always on"
        case .off: return "Off"
        }
    }
}

/// User settings. Plain values in UserDefaults; secrets in the Keychain.
@Observable
final class SettingsStore {
    private let d = UserDefaults.standard

    var googleMapsKey: String { didSet { Keychain.write(.googleMapsKey, googleMapsKey) } }
    var anthropicKey: String { didSet { Keychain.write(.anthropicKey, anthropicKey) } }
    var claudeModel: String { didSet { d.set(claudeModel, forKey: "claudeModel") } }
    var googleClientID: String { didSet { d.set(googleClientID, forKey: "googleClientID") } }
    var googleAccountEmail: String { didSet { d.set(googleAccountEmail, forKey: "googleAccountEmail") } }

    var homeLat: Double? { didSet { d.set(homeLat, forKey: "homeLat") } }
    var homeLng: Double? { didSet { d.set(homeLng, forKey: "homeLng") } }
    var tripMode: TripModeSetting { didSet { d.set(tripMode.rawValue, forKey: "tripMode") } }

    var discoveryEnabled: Bool { didSet { d.set(discoveryEnabled, forKey: "discoveryEnabled") } }
    var scenicEnabled: Bool { didSet { d.set(scenicEnabled, forKey: "scenicEnabled") } }
    var discoverNearHome: Bool { didSet { d.set(discoverNearHome, forKey: "discoverNearHome") } }
    var maxDiscoveryPerDay: Int { didSet { d.set(maxDiscoveryPerDay, forKey: "maxDiscoveryPerDay") } }
    var quietStart: Int { didSet { d.set(quietStart, forKey: "quietStart") } }
    var quietEnd: Int { didSet { d.set(quietEnd, forKey: "quietEnd") } }

    var metric: Bool { didSet { d.set(metric, forKey: "metric") } }
    var navApp: NavApp { didSet { d.set(navApp.rawValue, forKey: "navApp") } }
    var speechRate: Double { didSet { d.set(speechRate, forKey: "speechRate") } }
    var wikiLang: String { didSet { d.set(wikiLang, forKey: "wikiLang") } }
    var lastBudget: String { didSet { d.set(lastBudget, forKey: "lastBudget") } }
    var lastCuisine: String { didSet { d.set(lastCuisine, forKey: "lastCuisine") } }
    var onboarded: Bool { didSet { d.set(onboarded, forKey: "onboarded") } }

    init() {
        googleMapsKey = Keychain.read(.googleMapsKey)
        anthropicKey = Keychain.read(.anthropicKey)
        claudeModel = d.string(forKey: "claudeModel") ?? "claude-opus-5-5"
        googleClientID = d.string(forKey: "googleClientID") ?? ""
        googleAccountEmail = d.string(forKey: "googleAccountEmail") ?? ""
        homeLat = d.object(forKey: "homeLat") as? Double
        homeLng = d.object(forKey: "homeLng") as? Double
        tripMode = TripModeSetting(rawValue: d.string(forKey: "tripMode") ?? "") ?? .auto
        discoveryEnabled = d.object(forKey: "discoveryEnabled") as? Bool ?? true
        scenicEnabled = d.object(forKey: "scenicEnabled") as? Bool ?? true
        discoverNearHome = d.object(forKey: "discoverNearHome") as? Bool ?? false
        maxDiscoveryPerDay = d.object(forKey: "maxDiscoveryPerDay") as? Int ?? 3
        quietStart = d.object(forKey: "quietStart") as? Int ?? 22
        quietEnd = d.object(forKey: "quietEnd") as? Int ?? 8
        metric = d.object(forKey: "metric") as? Bool ?? (Locale.current.measurementSystem != .us)
        navApp = NavApp(rawValue: d.string(forKey: "navApp") ?? "") ?? .apple
        speechRate = d.object(forKey: "speechRate") as? Double ?? 0.5
        wikiLang = d.string(forKey: "wikiLang") ?? "en"
        lastBudget = d.string(forKey: "lastBudget") ?? Budget.mid.rawValue
        lastCuisine = d.string(forKey: "lastCuisine") ?? Cuisine.any.rawValue
        onboarded = d.bool(forKey: "onboarded")
    }

    var home: Coordinate? {
        get {
            guard let a = homeLat, let b = homeLng else { return nil }
            return Coordinate(lat: a, lng: b)
        }
        set {
            homeLat = newValue?.lat
            homeLng = newValue?.lng
        }
    }

    var alertSettings: AlertSettings {
        var s = AlertSettings()
        s.discoveryEnabled = discoveryEnabled
        s.scenicEnabled = scenicEnabled
        s.discoverNearHome = discoverNearHome
        s.maxDiscoveryPerDay = maxDiscoveryPerDay
        s.quietStartHour = quietStart
        s.quietEndHour = quietEnd
        return s
    }

    var hasGoogleKey: Bool { !googleMapsKey.isEmpty }
    var hasClaudeKey: Bool { !anthropicKey.isEmpty }
}
