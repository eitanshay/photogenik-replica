import Foundation

/// Two-minute spoken overviews. At a natural speaking pace (about 150 words a minute) two minutes is ~300 words;
/// the script targets 230 to 280 so it never runs over.
public enum Guide {
    public static let maxWords = 290
    public static let wordsPerMinute = 150.0

    public static let system = """
    You are a sharp, warm local guide speaking into someone's earbuds as they walk up to a place. \
    Write a script that will be read aloud by a text-to-speech voice.
    Rules:
    - 230 to 280 words. Never more than 290.
    - Plain spoken prose only: no headings, lists, emoji, stage directions, parentheses or URLs.
    - Open with the single most interesting thing, not "Welcome to".
    - Cover why it matters, one or two vivid stories or facts, and one specific thing to look for right now in person.
    - If it is a restaurant, cafe or shop, say what it is known for and what to order or notice.
    - Write numbers and dates the way they are spoken.
    - Use only facts from the source text or that you are certain of. If you are unsure of a detail, leave it out.
    - Reply with the script only.
    """

    public static func prompt(place: Place, source: String?, city: String?) -> String {
        var lines = ["Place: \(place.name)"]
        if let city = city, !city.isEmpty { lines.append("Where: \(city)") }
        if let a = place.address, !a.isEmpty { lines.append("Address: \(a)") }
        if let b = place.blurb, !b.isEmpty { lines.append("Type: \(b)") }
        if let n = place.note, !n.isEmpty { lines.append("The listener's own note: \(n)") }
        if let s = source, !s.isEmpty {
            lines.append("\nSource text:\n\(s)")
        } else {
            lines.append("\nNo source text was found. Rely only on what you reliably know about this exact place; if you know little, keep it short and say what kind of place it is and what to notice.")
        }
        return lines.joined(separator: "\n")
    }

    public static func wordCount(_ s: String) -> Int {
        s.split { $0.isWhitespace || $0.isNewline }.count
    }

    public static func estimatedSeconds(_ s: String) -> Int {
        Int((Double(wordCount(s)) / wordsPerMinute * 60).rounded())
    }

    /// Fallback when there is no Claude key: the start of the article, cut at a sentence end within the budget.
    public static func trim(_ text: String, maxWords: Int = maxWords) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"=+[^=]+=+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let words = cleaned.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count > maxWords else { return cleaned }
        let head = words.prefix(maxWords).joined(separator: " ")
        if let r = head.range(of: ". ", options: .backwards), head.distance(from: head.startIndex, to: r.lowerBound) > head.count / 2 {
            return String(head[..<r.lowerBound]) + "."
        }
        return head + "."
    }

    /// Cleans what the model sent back, in case it slipped in a heading or went long.
    public static func tidy(_ script: String) -> String {
        let lines = script.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.lowercased().hasPrefix("script:") }
        let joined = lines.joined(separator: "\n\n").replacingOccurrences(of: "*", with: "")
        return wordCount(joined) > maxWords + 20 ? trim(joined, maxWords: maxWords) : joined
    }
}

// MARK: - Trips from the calendar, places from trip docs

public struct TripEvent: Hashable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var coordinate: Coordinate?
    /// City name from reverse geocoding (set by the app).
    public var city: String?

    public init(title: String, start: Date, end: Date, location: String? = nil, coordinate: Coordinate? = nil, city: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.coordinate = coordinate
        self.city = city
    }
}

public struct Trip: Hashable, Sendable, Identifiable {
    public var city: String
    public var start: Date
    public var end: Date
    public var center: Coordinate?
    public var events: [TripEvent]
    public var id: String { "\(city)|\(Int(start.timeIntervalSince1970))" }
}

public enum TripPlanner {
    /// Groups events at least `minKm` from home into trips by city; events in the same city within
    /// `gapDays` of each other form one trip.
    public static func trips(from events: [TripEvent], home: Coordinate?, minKm: Double = 100, gapDays: Double = 3) -> [Trip] {
        let away = events.filter { e in
            guard let c = e.coordinate, let h = home else { return false }
            return Geo.distance(c, h) >= minKm * 1000
        }.sorted { $0.start < $1.start }
        var trips: [Trip] = []
        for e in away {
            let city = e.city ?? e.location ?? "Trip"
            if let i = trips.lastIndex(where: { $0.city == city }), e.start.timeIntervalSince(trips[i].end) < gapDays * 86_400 {
                trips[i].events.append(e)
                trips[i].end = max(trips[i].end, e.end)
            } else {
                trips.append(Trip(city: city, start: e.start, end: e.end, center: e.coordinate, events: [e]))
            }
        }
        return trips
    }

    /// The trip you are on right now (by date, or by being within 60 km of its center).
    public static func current(_ trips: [Trip], now: Date, here: Coordinate?) -> Trip? {
        if let h = here, let t = trips.first(where: { t in t.center.map { Geo.distance($0, h) < 60_000 } ?? false && now < t.end.addingTimeInterval(86_400) }) {
            return t
        }
        return trips.first { now >= $0.start.addingTimeInterval(-86_400) && now <= $0.end.addingTimeInterval(86_400) }
    }
}

public struct ExtractedPlace: Codable, Hashable, Sendable {
    public var name: String
    public var city: String?
    public var note: String?
    public var type: String?
}

public enum DocExtraction {
    public static let system = """
    You read travel documents (itineraries, bookings, recommendation lists) and pull out every specific place \
    someone might go: restaurants, cafes, bars, sights, museums, viewpoints, shops, hotels and meeting points. \
    Reply with JSON only, no prose: {"places":[{"name":"...","city":"...","note":"...","type":"food|coffee|sight|scenic|hotel|other"}]}. \
    The note is at most 15 words: why it is on the list, a reservation time, or a dish to order, taken from the document. \
    Skip generic mentions ("a nice cafe") and places with no name.
    """

    public static func prompt(docTitle: String, text: String, destination: String?) -> String {
        var s = "Document: \(docTitle)\n"
        if let d = destination { s += "Trip destination: \(d)\n" }
        s += "\n" + String(text.prefix(40_000))
        return s
    }

    public static func parse(_ reply: String) -> [ExtractedPlace] {
        var t = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}") { t = String(t[start...end]) }
        struct Wrapper: Codable { var places: [ExtractedPlace] }
        guard let data = t.data(using: .utf8), let w = try? JSONDecoder().decode(Wrapper.self, from: data) else { return [] }
        return w.places.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
