import Foundation

/// iOS monitors at most 20 regions per app. The planner keeps the closest 19 places armed and uses the
/// 20th as a "you moved" boundary around you; leaving it (or a significant-change update) re-plans.
public struct GeofenceRegion: Hashable, Sendable {
    public var id: String
    public var center: Coordinate
    public var radius: Double
}

public struct GeofencePlan: Sendable {
    public var regions: [GeofenceRegion]
    public var refresh: GeofenceRegion
    /// Places you are already inside (iOS will not report an entry for these), so the caller can alert now.
    public var alreadyInside: [String]
}

public enum GeofencePlanner {
    public static let refreshID = "roam.refresh"
    public static let prefix = "roam.p."

    public static func regionID(for placeID: String) -> String { prefix + placeID }
    public static func placeID(from regionID: String) -> String? {
        regionID.hasPrefix(prefix) ? String(regionID.dropFirst(prefix.count)) : nil
    }

    /// Trigger radius by kind. iOS region entry is reliable from about 100 m; smaller circles get missed.
    public static func radius(for p: Place) -> Double {
        switch p.kind {
        case .saved: return 150
        case .attraction: return 130
        case .scenic: return 200
        }
    }

    public static func plan(from here: Coordinate, places: [Place], maxRegions: Int = 20,
                            maxDistance: Double = 30_000, maxRegionRadius: Double = 5_000) -> GeofencePlan {
        let slots = max(1, maxRegions - 1)
        var inside: [String] = []
        let candidates: [(Place, Double, Double)] = places.compactMap { p in
            guard !p.muted, let c = p.coordinate, c.isValid else { return nil }
            let d = Geo.distance(here, c)
            guard d <= maxDistance else { return nil }
            if d < radius(for: p) {
                inside.append(p.id)
                return nil
            }
            // Saved places count as closer than they are, so they win slots over discoveries.
            let weight = p.kind == .saved ? 1.6 : (0.8 + 0.4 * MathX.clamp(p.score, 0, 1))
            return (p, d, d / weight)
        }
        let chosen = candidates.sorted { $0.2 < $1.2 }.prefix(slots)
        let regions = chosen.map { GeofenceRegion(id: regionID(for: $0.0.id), center: $0.0.coordinate!, radius: radius(for: $0.0)) }
        let farthest = chosen.map { $0.1 }.max() ?? maxRegionRadius * 2
        let refreshRadius = MathX.clamp(farthest * 0.5, 400, maxRegionRadius)
        return GeofencePlan(regions: Array(regions),
                            refresh: GeofenceRegion(id: refreshID, center: here, radius: refreshRadius),
                            alreadyInside: inside)
    }
}

public struct AlertSettings: Codable, Equatable, Sendable {
    public var discoveryEnabled: Bool = true
    public var scenicEnabled: Bool = true
    public var maxDiscoveryPerDay: Int = 3
    public var maxSavedPerDay: Int = 8
    public var quietStartHour: Int = 22
    public var quietEndHour: Int = 8
    /// Discovery alerts only on trips unless this is on.
    public var discoverNearHome: Bool = false

    public init() {}
}

public enum AlertDecision: Equatable, Sendable {
    case allow
    case deny(String)
}

public struct AlertLogEntry: Codable, Hashable, Sendable {
    public var placeID: String
    public var date: Date
    public var discovery: Bool

    public init(placeID: String, date: Date, discovery: Bool) {
        self.placeID = placeID
        self.date = date
        self.discovery = discovery
    }
}

public enum AlertPolicy {
    /// Whether to notify for `place` now. `speed` is meters/second from the latest fix (negative or nil if unknown).
    public static func decide(place: Place, now: Date, hour: Int, tripMode: Bool, speed: Double?,
                              log: [AlertLogEntry], settings: AlertSettings) -> AlertDecision {
        if place.muted { return .deny("muted") }
        if inQuietHours(hour: hour, start: settings.quietStartHour, end: settings.quietEndHour) { return .deny("quiet hours") }
        if let s = speed, s > 8 { return .deny("moving too fast") }

        let discovery = place.isDiscovered
        if discovery {
            if !settings.discoveryEnabled && place.kind == .attraction { return .deny("discovery off") }
            if !settings.scenicEnabled && place.kind == .scenic { return .deny("scenic off") }
            if !tripMode && !settings.discoverNearHome { return .deny("not on a trip") }
        }

        // Cooldown per place: on a trip you may pass the same spot again the next day; at home you pass
        // your saved places all the time, so they stay quiet for two weeks after an alert.
        let cooldown: TimeInterval
        if discovery { cooldown = 30 * 86_400 }
        else { cooldown = tripMode ? 12 * 3_600 : 14 * 86_400 }
        if let last = place.lastAlertAt, now.timeIntervalSince(last) < cooldown { return .deny("alerted recently") }

        let dayAgo = now.addingTimeInterval(-86_400)
        let recent = log.filter { $0.date > dayAgo }
        if recent.contains(where: { $0.date > now.addingTimeInterval(-300) }) && discovery {
            return .deny("another alert a moment ago")
        }
        let count = recent.filter { $0.discovery == discovery }.count
        let cap = discovery ? settings.maxDiscoveryPerDay : settings.maxSavedPerDay
        if count >= cap { return .deny("daily cap") }
        return .allow
    }

    public static func inQuietHours(hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }

    /// Trip mode: farther than `km` from home. With no home set, only manual trip mode counts.
    public static func isTripMode(here: Coordinate?, home: Coordinate?, km: Double = 50) -> Bool {
        guard let h = here, let home = home else { return false }
        return Geo.distance(h, home) > km * 1000
    }
}

public struct AlertText: Equatable, Sendable {
    public var title: String
    public var body: String
}

public enum AlertComposer {
    public static func compose(place: Place, distance: Double, metric: Bool, goldenStartsIn minutes: Int?) -> AlertText {
        let walk = Geo.walkingMinutes(distance)
        let away = walk <= 1 ? "right here" : "\(walk) min walk"
        switch place.kind {
        case .saved:
            var body: [String] = []
            if let n = place.note, !n.isEmpty { body.append(n) }
            else if let l = place.lists.first { body.append("From your \(l) list") }
            if place.scenic, let m = minutesText(minutes) { body.append(m) }
            body.append("Tap to navigate or hear about it.")
            return AlertText(title: "\(place.name) · \(away)", body: body.joined(separator: " "))
        case .attraction:
            let blurb = place.blurb.map { $0.prefix(1).uppercased() + $0.dropFirst() + ". " } ?? ""
            return AlertText(title: "Worth a look: \(place.name)", body: "\(blurb)\(away.capitalizedFirst). Tap to hear a 2-minute story.")
        case .scenic:
            var body = "Photogenic spot, \(away)."
            if let m = minutesText(minutes) { body += " " + m }
            return AlertText(title: "Scenic: \(place.name)", body: body)
        }
    }

    static func minutesText(_ minutes: Int?) -> String? {
        guard let m = minutes else { return nil }
        if m <= 0 { return "Golden hour now." }
        if m <= 90 { return "Golden hour in \(m) min." }
        return nil
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
