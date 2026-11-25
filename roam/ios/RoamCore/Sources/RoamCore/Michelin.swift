import Foundation

public enum MichelinAward: Int, Codable, Sendable, Comparable {
    case selected = 0, bib = 1, star1 = 2, star2 = 3, star3 = 4

    public static func < (a: MichelinAward, b: MichelinAward) -> Bool { a.rawValue < b.rawValue }

    public init?(text: String) {
        let t = text.lowercased()
        if t.contains("3 star") { self = .star3 }
        else if t.contains("2 star") { self = .star2 }
        else if t.contains("1 star") { self = .star1 }
        else if t.contains("bib") { self = .bib }
        else if t.contains("selected") { self = .selected }
        else { return nil }
    }

    public var label: String {
        switch self {
        case .selected: return "Michelin selected"
        case .bib: return "Bib Gourmand"
        case .star1: return "1 Michelin star"
        case .star2: return "2 Michelin stars"
        case .star3: return "3 Michelin stars"
        }
    }

    public var short: String {
        switch self {
        case .selected: return "MICHELIN"
        case .bib: return "BIB"
        case .star1: return "★"
        case .star2: return "★★"
        case .star3: return "★★★"
        }
    }
}

public struct MichelinRestaurant: Codable, Hashable, Sendable {
    public var name: String
    public var coordinate: Coordinate
    /// 1...4 from the guide's currency symbols.
    public var price: Int
    public var cuisine: String
    public var award: MichelinAward
    public var city: String
    public var url: String

    public init(name: String, coordinate: Coordinate, price: Int, cuisine: String, award: MichelinAward, city: String, url: String) {
        self.name = name
        self.coordinate = coordinate
        self.price = price
        self.cuisine = cuisine
        self.award = award
        self.city = city
        self.url = url
    }
}

/// Parses the open michelin-my-maps dataset (github.com/ngshiheng/michelin-my-maps) and the compact
/// tab-separated copy bundled with the app.
public enum Michelin {
    public static let datasetURL = URL(string: "https://raw.githubusercontent.com/ngshiheng/michelin-my-maps/main/data/michelin_my_maps.csv")!

    /// Number of currency symbols ("$$", "€€€", "¥") clamped to 1...4; 2 when unknown.
    public static func priceLevel(_ s: String) -> Int {
        let n = s.trimmingCharacters(in: .whitespaces).count
        return n == 0 ? 2 : min(4, max(1, n))
    }

    public static func parseDatasetCSV(_ text: String) -> [MichelinRestaurant] {
        CSV.records(text).compactMap { r in
            guard let name = r["name"], !name.isEmpty,
                  let lat = Double(r["latitude"] ?? ""), let lng = Double(r["longitude"] ?? ""),
                  let award = MichelinAward(text: r["award"] ?? "") else { return nil }
            let c = Coordinate(lat: lat, lng: lng)
            guard c.isValid else { return nil }
            return MichelinRestaurant(name: name, coordinate: c, price: priceLevel(r["price"] ?? ""),
                                      cuisine: r["cuisine"] ?? "", award: award,
                                      city: r["location"] ?? "", url: r["url"] ?? "")
        }
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }

    /// name, lat, lng, price, cuisine, award, city, url: one restaurant per line.
    public static func encodeCompact(_ items: [MichelinRestaurant]) -> String {
        items.map { m in
            [clean(m.name), String(format: "%.6f", m.coordinate.lat), String(format: "%.6f", m.coordinate.lng),
             String(m.price), clean(m.cuisine), String(m.award.rawValue), clean(m.city), clean(m.url)]
                .joined(separator: "\t")
        }.joined(separator: "\n")
    }

    public static func decodeCompact(_ text: String) -> [MichelinRestaurant] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 8, let lat = Double(f[1]), let lng = Double(f[2]),
                  let price = Int(f[3]), let a = Int(f[5]), let award = MichelinAward(rawValue: a) else { return nil }
            return MichelinRestaurant(name: f[0], coordinate: Coordinate(lat: lat, lng: lng), price: price,
                                      cuisine: f[4], award: award, city: f[6], url: f[7])
        }
    }

    public static func index(_ items: [MichelinRestaurant]) -> GridIndex<MichelinRestaurant> {
        var g = GridIndex<MichelinRestaurant>(cellDegrees: 0.05)
        for m in items { g.insert(m, at: m.coordinate) }
        return g
    }
}
