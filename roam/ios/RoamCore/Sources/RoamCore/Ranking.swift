import Foundation

public enum Budget: String, CaseIterable, Codable, Sendable {
    case any, low, mid, high

    public var label: String {
        switch self {
        case .any: return "Any"
        case .low: return "$"
        case .mid: return "$$"
        case .high: return "$$$"
        }
    }

    /// Price level 1...4 (Michelin symbols or Google PRICE_LEVEL_*). Unknown prices pass.
    /// Bands overlap on purpose: most Bib Gourmands sit at 2, which is fair game for low and mid.
    public func allows(_ price: Int?) -> Bool {
        guard let p = price else { return true }
        switch self {
        case .any: return true
        case .low: return p <= 2
        case .mid: return p >= 2 && p <= 3
        case .high: return p >= 3
        }
    }
}

public enum Cuisine: String, CaseIterable, Codable, Sendable {
    case any, japanese, italian, french, spanish, mediterranean, middleEastern, chinese, korean, thai,
         vietnamese, indian, mexican, seafood, steak, pizza, vegetarian, american, bakery

    public var label: String {
        switch self {
        case .any: return "Any"
        case .middleEastern: return "Middle Eastern"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    var keywords: [String] {
        switch self {
        case .any: return []
        case .japanese: return ["japanese", "sushi", "ramen", "izakaya", "tempura", "yakitori", "kaiseki", "udon", "soba", "tonkatsu", "omakase"]
        case .italian: return ["italian", "pasta", "trattoria", "osteria", "pizzeria"]
        case .french: return ["french", "bistro", "brasserie", "bouchon"]
        case .spanish: return ["spanish", "tapas", "basque", "catalan", "andalusian"]
        case .mediterranean: return ["mediterranean", "greek", "portuguese", "seafood mediterranean"]
        case .middleEastern: return ["middle eastern", "lebanese", "israeli", "turkish", "persian", "iranian", "levant", "syrian", "falafel", "shawarma"]
        case .chinese: return ["chinese", "cantonese", "sichuan", "szechuan", "dim sum", "dumpling", "taiwanese", "shanghainese", "hunanese", "noodles"]
        case .korean: return ["korean", "bbq korean"]
        case .thai: return ["thai"]
        case .vietnamese: return ["vietnamese", "pho", "banh mi"]
        case .indian: return ["indian", "south indian", "north indian", "pakistani", "sri lankan", "nepalese"]
        case .mexican: return ["mexican", "taqueria", "tacos", "oaxacan", "yucatan"]
        case .seafood: return ["seafood", "fish", "oyster", "fish and seafood"]
        case .steak: return ["steak", "steakhouse", "grill", "meats and grills", "barbecue", "bbq"]
        case .pizza: return ["pizza", "pizzeria"]
        case .vegetarian: return ["vegetarian", "vegan", "plant"]
        case .american: return ["american", "burger", "diner", "southern", "californian"]
        case .bakery: return ["bakery", "patisserie", "boulangerie", "pastry"]
        }
    }

    /// Google Places (New) type names for this cuisine.
    public var googleTypes: [String] {
        switch self {
        case .any: return []
        case .japanese: return ["japanese_restaurant", "sushi_restaurant", "ramen_restaurant"]
        case .italian: return ["italian_restaurant", "pizza_restaurant"]
        case .french: return ["french_restaurant"]
        case .spanish: return ["spanish_restaurant"]
        case .mediterranean: return ["mediterranean_restaurant", "greek_restaurant"]
        case .middleEastern: return ["middle_eastern_restaurant", "lebanese_restaurant", "turkish_restaurant"]
        case .chinese: return ["chinese_restaurant"]
        case .korean: return ["korean_restaurant"]
        case .thai: return ["thai_restaurant"]
        case .vietnamese: return ["vietnamese_restaurant"]
        case .indian: return ["indian_restaurant"]
        case .mexican: return ["mexican_restaurant"]
        case .seafood: return ["seafood_restaurant"]
        case .steak: return ["steak_house", "barbecue_restaurant"]
        case .pizza: return ["pizza_restaurant"]
        case .vegetarian: return ["vegetarian_restaurant", "vegan_restaurant"]
        case .american: return ["american_restaurant", "hamburger_restaurant"]
        case .bakery: return ["bakery"]
        }
    }

    /// Text for a Google text search ("japanese restaurant").
    public var searchPhrase: String {
        switch self {
        case .any: return "restaurant"
        case .bakery: return "bakery"
        case .pizza: return "pizza"
        case .steak: return "steakhouse"
        default: return "\(label.lowercased()) restaurant"
        }
    }

    public func matches(text: String, types: [String]) -> Bool {
        if self == .any { return true }
        let t = text.lowercased()
        if keywords.contains(where: { t.contains($0) }) { return true }
        return types.contains { googleTypes.contains($0) }
    }
}

public enum VenueSource: String, Codable, Sendable {
    case google, apple, michelin, osm, refuge
}

public struct Venue: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var coordinate: Coordinate
    public var source: VenueSource
    public var rating: Double?
    public var ratingCount: Int?
    public var priceLevel: Int?
    public var types: [String]
    public var openNow: Bool?
    public var address: String?
    public var mapsURL: String?
    public var michelin: MichelinAward?
    public var michelinURL: String?
    public var cuisine: String?
    /// OSM tags or Refuge flags (fee, access, unisex, accessible).
    public var tags: [String: String]

    public init(id: String, name: String, coordinate: Coordinate, source: VenueSource, rating: Double? = nil,
                ratingCount: Int? = nil, priceLevel: Int? = nil, types: [String] = [], openNow: Bool? = nil,
                address: String? = nil, mapsURL: String? = nil, michelin: MichelinAward? = nil,
                michelinURL: String? = nil, cuisine: String? = nil, tags: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.source = source
        self.rating = rating
        self.ratingCount = ratingCount
        self.priceLevel = priceLevel
        self.types = types
        self.openNow = openNow
        self.address = address
        self.mapsURL = mapsURL
        self.michelin = michelin
        self.michelinURL = michelinURL
        self.cuisine = cuisine
        self.tags = tags
    }

    public init(michelin m: MichelinRestaurant) {
        self.init(id: "michelin:\(m.url.isEmpty ? m.name : m.url)", name: m.name, coordinate: m.coordinate,
                  source: .michelin, priceLevel: m.price, michelin: m.award, michelinURL: m.url, cuisine: m.cuisine)
    }
}

public struct RankedVenue: Identifiable, Hashable, Sendable {
    public var venue: Venue
    public var distance: Double
    public var walkMinutes: Int
    public var score: Double
    /// Short reason it ranked here ("Bib Gourmand · Japanese", "4.7 from 1.2k reviews").
    public var reason: String
    public var id: String { venue.id }
}

public enum Ranker {
    /// Bayesian average: pulls ratings with few reviews toward the prior mean.
    public static func bayes(rating: Double, count: Int, priorMean: Double, priorWeight: Double) -> Double {
        let v = Double(max(0, count))
        return (v * rating + priorWeight * priorMean) / (v + priorWeight)
    }

    static let coffeeChains = ["starbucks", "dunkin", "costa coffee", "tim hortons", "peet", "caribou", "pret a manger",
                               "mccafe", "mcdonald", "gloria jean", "coffee bean & tea leaf", "the coffee bean", "biggby",
                               "dutch bros", "second cup", "caffe nero", "caffè nero", "tchibo", "lavazza", "nespresso",
                               "7-eleven", "seven eleven", "doutor", "tully", "excelsior", "aroma espresso", "cafe cafe",
                               "greggs", "panera", "krispy kreme"]

    public static func isChain(_ name: String) -> Bool {
        let n = name.lowercased()
        return coffeeChains.contains { n.contains($0) }
    }

    public static func looksSpecialty(_ name: String, types: [String]) -> Bool {
        let n = name.lowercased()
        let words = ["roaster", "roastery", "roasting", "espresso bar", "specialty", "coffee lab", "brew bar", "pour over", "filter"]
        return words.contains { n.contains($0) } || types.contains("coffee_roastery")
    }

    static func ratingText(_ v: Venue) -> String? {
        guard let r = v.rating, let c = v.ratingCount, c > 0 else { return nil }
        let count = c >= 1000 ? String(format: "%.1fk", Double(c) / 1000) : "\(c)"
        return String(format: "%.1f", r) + " from \(count) reviews"
    }

    // MARK: Coffee: always the best within a walkable radius.

    public static func coffee(_ venues: [Venue], from here: Coordinate, maxWalkMinutes: Int = 20) -> [RankedVenue] {
        let ranked: [RankedVenue] = venues.compactMap { v in
            if v.openNow == false { return nil }
            let d = Geo.distance(here, v.coordinate)
            let walk = Geo.walkingMinutes(d)
            guard walk <= maxWalkMinutes else { return nil }
            var score: Double
            var reasons: [String] = []
            if let r = v.rating, let c = v.ratingCount, c >= 15 {
                score = bayes(rating: r, count: c, priorMean: 4.3, priorWeight: 60)
                if let t = ratingText(v) { reasons.append(t) }
            } else if v.source == .apple || v.source == .osm {
                score = 4.0
            } else {
                return nil
            }
            if looksSpecialty(v.name, types: v.types) {
                score += 0.15
                reasons.append("specialty")
            }
            if isChain(v.name) { score -= 0.6 }
            // Coffee should be the best one, so distance only costs after a short walk.
            score -= 0.02 * Double(max(0, walk - 6))
            if v.openNow == nil { score -= 0.05 }
            return RankedVenue(venue: v, distance: d, walkMinutes: walk, score: score,
                               reason: reasons.isEmpty ? "nearby" : reasons.joined(separator: " · "))
        }
        return ranked.sorted { $0.score > $1.score }
    }

    // MARK: Food: Michelin first (Bib Gourmand for low and mid, stars for high), then well-rated places.

    public static func awardWeight(_ a: MichelinAward, budget: Budget) -> Double {
        if budget == .high {
            switch a {
            case .star3: return 3.6
            case .star2: return 3.4
            case .star1: return 3.2
            case .bib: return 2.8
            case .selected: return 2.2
            }
        }
        switch a {
        case .bib: return 3.0
        case .star1, .star2, .star3: return 2.8
        case .selected: return 2.2
        }
    }

    public static func food(_ venues: [Venue], from here: Coordinate, budget: Budget, cuisine: Cuisine,
                            maxWalkMinutes: Int = 25) -> [RankedVenue] {
        let ranked: [RankedVenue] = venues.compactMap { v in
            if v.openNow == false { return nil }
            guard budget.allows(v.priceLevel) else { return nil }
            guard cuisine.matches(text: (v.cuisine ?? "") + " " + v.name, types: v.types) else { return nil }
            let d = Geo.distance(here, v.coordinate)
            let walk = Geo.walkingMinutes(d)
            guard walk <= maxWalkMinutes else { return nil }
            var score: Double
            var reasons: [String] = []
            if let a = v.michelin {
                score = awardWeight(a, budget: budget)
                reasons.append(a.label)
                if let c = v.cuisine, !c.isEmpty { reasons.append(c) }
                if let r = v.rating, let c = v.ratingCount, c >= 30 {
                    score += 0.3 * (bayes(rating: r, count: c, priorMean: 4.3, priorWeight: 100) - 4.3)
                }
            } else if let r = v.rating, let c = v.ratingCount, c >= 40 {
                let b = bayes(rating: r, count: c, priorMean: 4.2, priorWeight: 150)
                score = 2.0 + (b - 4.5) * 2
                if let t = ratingText(v) { reasons.append(t) }
            } else {
                return nil
            }
            if budget == .low, let p = v.priceLevel { score -= 0.1 * Double(p - 1) }
            score -= 0.04 * Double(max(0, walk - 8))
            if v.openNow == nil { score -= 0.2 }
            return RankedVenue(venue: v, distance: d, walkMinutes: walk, score: score, reason: reasons.joined(separator: " · "))
        }
        return ranked.sorted { $0.score > $1.score }
    }

    // MARK: Restroom: mostly the nearest, with a small cost for "customers only" and paid ones.

    public static func restroom(_ venues: [Venue], from here: Coordinate) -> [RankedVenue] {
        var seen: [Coordinate] = []
        let ranked: [RankedVenue] = venues.compactMap { v in
            let d = Geo.distance(here, v.coordinate)
            let walk = Geo.walkingMinutes(d)
            var cost = Double(walk)
            var reasons: [String] = []
            let isProxy = v.tags["proxy"] == "1"
            if isProxy {
                cost += 3
                reasons.append("usually has a restroom")
            } else {
                reasons.append(v.source == .refuge ? "listed on Refuge" : "public restroom")
            }
            if v.tags["fee"] == "yes" { cost += 1; reasons.append("paid") }
            if v.tags["access"] == "customers" { cost += 2; reasons.append("customers") }
            if v.tags["access"] == "private" || v.tags["access"] == "no" { return nil }
            if v.openNow == false { return nil }
            return RankedVenue(venue: v, distance: d, walkMinutes: walk, score: -cost, reason: reasons.joined(separator: " · "))
        }
        // Collapse duplicates from several sources (the same toilet in OSM and Apple).
        return ranked.sorted { $0.score > $1.score }.filter { r in
            if seen.contains(where: { Geo.distance($0, r.venue.coordinate) < 25 }) { return false }
            seen.append(r.venue.coordinate)
            return true
        }
    }

    // MARK: Matching across sources

    public static func sameName(_ a: String, _ b: String) -> Bool {
        let fa = Place.fold(a), fb = Place.fold(b)
        if fa.isEmpty || fb.isEmpty { return false }
        if fa == fb || fa.contains(fb) || fb.contains(fa) { return true }
        let ta = Set(a.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        let tb = Set(b.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        guard !ta.isEmpty, !tb.isEmpty else { return false }
        return Double(ta.intersection(tb).count) / Double(ta.union(tb).count) >= 0.5
    }

    /// Michelin rows enriched with Google's open-now, rating and link when the same place is found nearby;
    /// Google places that matched are dropped so each restaurant appears once.
    public static func merge(michelin: [Venue], google: [Venue]) -> [Venue] {
        var used = Set<String>()
        var out: [Venue] = michelin.map { m in
            guard let g = google.first(where: { !used.contains($0.id) && sameName($0.name, m.name)
                && Geo.distance($0.coordinate, m.coordinate) < 200 }) else { return m }
            used.insert(g.id)
            var v = m
            v.rating = g.rating
            v.ratingCount = g.ratingCount
            v.openNow = g.openNow
            v.types = g.types
            v.mapsURL = g.mapsURL
            v.address = g.address ?? m.address
            v.id = g.id
            return v
        }
        out += google.filter { !used.contains($0.id) }
        return out
    }
}
