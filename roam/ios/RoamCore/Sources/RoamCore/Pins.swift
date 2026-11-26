import Foundation

/// What a pin on the map is. Each has its own icon and color in the app.
public enum PinCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case saved, sight, scenic, coffee, food, restroom
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .saved: return "Saved"
        case .sight: return "Sights"
        case .scenic: return "Scenic"
        case .coffee: return "Coffee"
        case .food: return "Food"
        case .restroom: return "Restroom"
        }
    }

    /// Singular, for the card.
    public var noun: String {
        switch self {
        case .saved: return "saved place"
        case .sight: return "sight"
        case .scenic: return "scenic spot"
        case .coffee: return "coffee"
        case .food: return "restaurant"
        case .restroom: return "restroom"
        }
    }

    /// Layers from your library (always available) versus searches run on demand.
    public var isSearch: Bool { self == .coffee || self == .food || self == .restroom }

    public static func of(_ p: Place) -> PinCategory {
        switch p.kind {
        case .saved: return .saved
        case .attraction: return p.scenic ? .scenic : .sight
        case .scenic: return .scenic
        }
    }
}

/// One thing on the map: a place from your library, or a venue from a coffee, food or restroom search.
public struct Pin: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var coordinate: Coordinate
    public var category: PinCategory
    /// Library place, when it is one.
    public var placeID: String?
    public var venue: Venue?
    /// 1-based position in its search results (1 = best pick), nil for library places.
    public var rank: Int?
    public var rankOf: Int?
    public var reason: String?
    /// A few words to describe it.
    public var words: String?
    /// Higher shows on top when pins overlap.
    public var prominence: Double

    public init(place p: Place) {
        id = "place:" + p.id
        name = p.name
        coordinate = p.coordinate ?? Coordinate(lat: 0, lng: 0)
        category = PinCategory.of(p)
        placeID = p.id
        venue = nil
        rank = nil
        rankOf = nil
        reason = nil
        words = PinText.words(for: p)
        prominence = p.kind == .saved ? 1 : p.score * 0.8
    }

    public init(ranked r: RankedVenue, category: PinCategory, rank: Int, of total: Int) {
        id = "\(category.rawValue):" + r.venue.id
        name = r.venue.name
        coordinate = r.venue.coordinate
        self.category = category
        placeID = nil
        venue = r.venue
        self.rank = rank
        rankOf = total
        reason = r.reason
        words = PinText.words(for: r.venue, reason: r.reason)
        prominence = 2 - Double(rank) * 0.05
    }

    public var isMichelin: Bool { venue?.michelin != nil }
}

public enum PinText {
    /// 1234 -> "1.2k", 12345 -> "12k".
    public static func compactCount(_ n: Int) -> String {
        if n >= 10_000 { return "\(n / 1000)k" }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1000).replacingOccurrences(of: ".0k", with: "k") }
        return "\(n)"
    }

    /// "★ 4.7 (1.2k)" or nil.
    public static func rating(_ v: Venue) -> String? {
        guard let r = v.rating else { return nil }
        let base = String(format: "★ %.1f", r)
        guard let c = v.ratingCount, c > 0 else { return base }
        return "\(base) (\(compactCount(c)))"
    }

    public static func price(_ v: Venue) -> String? {
        guard let p = v.priceLevel, p > 0 else { return nil }
        return String(repeating: "$", count: min(4, p))
    }

    /// "Best coffee nearby", "#2 of 8".
    public static func rank(_ pin: Pin) -> String? {
        guard let r = pin.rank else { return nil }
        if r == 1 {
            switch pin.category {
            case .restroom: return "Nearest restroom"
            case .food: return "Best pick nearby"
            default: return "Best \(pin.category.noun) nearby"
            }
        }
        if let n = pin.rankOf { return "#\(r) of \(n)" }
        return "#\(r)"
    }

    /// Up to about 8 words: your note, else the description, else the list it came from.
    public static func words(for p: Place) -> String? {
        let candidates = [p.note, p.blurb, p.lists.first.map { "From \($0)" }]
        guard let s = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        return shorten(s)
    }

    public static func words(for v: Venue, reason: String) -> String? {
        var bits: [String] = []
        if let m = v.michelin { bits.append(m.label) }
        if let c = v.cuisine, !c.isEmpty { bits.append(c.capitalized) }
        if bits.isEmpty { return shorten(reason) }
        return bits.joined(separator: " · ")
    }

    /// Trims to roughly `maxWords` words, ending with an ellipsis if cut.
    public static func shorten(_ s: String, maxWords: Int = 9) -> String {
        let words = s.split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard words.count > maxWords else { return s.prefix(1).uppercased() + s.dropFirst() }
        let cut = words.prefix(maxWords).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",;:.-"))
        return cut.prefix(1).uppercased() + cut.dropFirst() + "…"
    }

    /// Pins of one category in the order the card steps through them: rank, else distance from `from`.
    public static func ordered(_ pins: [Pin], category: PinCategory, from: Coordinate?) -> [Pin] {
        let same = pins.filter { $0.category == category }
        if same.contains(where: { $0.rank != nil }) {
            return same.sorted { ($0.rank ?? .max) < ($1.rank ?? .max) }
        }
        guard let h = from else { return same.sorted { $0.name < $1.name } }
        return same.sorted { Geo.distance(h, $0.coordinate) < Geo.distance(h, $1.coordinate) }
    }
}
