import Foundation

public enum PlaceKind: String, Codable, CaseIterable, Sendable {
    /// Something you saved (Google Maps import, share sheet, a trip doc, or added by hand).
    case saved
    /// Discovered nearby: a notable sight from Wikipedia or OpenStreetMap.
    case attraction
    /// Discovered nearby: a viewpoint or other photogenic spot.
    case scenic

    public var label: String {
        switch self {
        case .saved: return "Saved"
        case .attraction: return "Worth a look"
        case .scenic: return "Scenic"
        }
    }
}

public enum PlaceSource: String, Codable, Sendable {
    case takeout, share, manual, doc, wikipedia, osm
}

public struct Place: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var coordinate: Coordinate?
    public var kind: PlaceKind
    public var source: PlaceSource
    /// Google Maps list names or "Doc: <title>" for places pulled from a trip doc.
    public var lists: [String]
    public var note: String?
    public var address: String?
    /// Original link (Google Maps URL, Wikipedia page, doc link).
    public var url: String?
    public var googlePlaceID: String?
    public var wikipediaTitle: String?
    public var wikipediaLang: String?
    /// One-line description (Wikipedia short description, OSM type).
    public var blurb: String?
    /// Photogenic: viewpoints, waterfalls, lighthouses, or anything you flag.
    public var scenic: Bool
    /// Discovery quality, 0...1 (higher is more notable). Saved places are 1.
    public var score: Double
    public var addedAt: Date
    public var lastAlertAt: Date?
    public var muted: Bool
    public var guideScript: String?
    public var resolveAttempts: Int

    public init(id: String = UUID().uuidString, name: String, coordinate: Coordinate? = nil,
                kind: PlaceKind = .saved, source: PlaceSource = .manual, lists: [String] = [],
                note: String? = nil, address: String? = nil, url: String? = nil,
                googlePlaceID: String? = nil, wikipediaTitle: String? = nil, wikipediaLang: String? = nil,
                blurb: String? = nil, scenic: Bool = false, score: Double = 1, addedAt: Date = Date(),
                lastAlertAt: Date? = nil, muted: Bool = false, guideScript: String? = nil, resolveAttempts: Int = 0) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.kind = kind
        self.source = source
        self.lists = lists
        self.note = note
        self.address = address
        self.url = url
        self.googlePlaceID = googlePlaceID
        self.wikipediaTitle = wikipediaTitle
        self.wikipediaLang = wikipediaLang
        self.blurb = blurb
        self.scenic = scenic
        self.score = score
        self.addedAt = addedAt
        self.lastAlertAt = lastAlertAt
        self.muted = muted
        self.guideScript = guideScript
        self.resolveAttempts = resolveAttempts
    }

    public var isResolved: Bool { coordinate?.isValid == true }
    public var isDiscovered: Bool { kind != .saved }

    /// Name folded for duplicate detection: lowercase, no accents, no punctuation.
    public static func fold(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}

/// The in-memory collection with merge rules. Pure value type so it is testable anywhere.
public struct PlaceLibrary: Codable, Sendable {
    public var places: [Place]
    public var version: Int

    public init(places: [Place] = [], version: Int = 1) {
        self.places = places
        self.version = version
    }

    public var saved: [Place] { places.filter { $0.kind == .saved } }
    public var discovered: [Place] { places.filter { $0.isDiscovered } }
    public var unresolved: [Place] { places.filter { !$0.isResolved && $0.resolveAttempts < 3 } }

    public func place(id: String) -> Place? { places.first { $0.id == id } }

    /// Index of an existing place that is the same real-world place as `p`, if any.
    public func matchIndex(for p: Place) -> Int? {
        if let gid = p.googlePlaceID, let i = places.firstIndex(where: { $0.googlePlaceID == gid }) { return i }
        if let w = p.wikipediaTitle, let i = places.firstIndex(where: { $0.wikipediaTitle == w && $0.wikipediaLang == p.wikipediaLang }) { return i }
        if let u = p.url, !u.isEmpty, let i = places.firstIndex(where: { $0.url == u }) { return i }
        let name = Place.fold(p.name)
        guard !name.isEmpty else { return nil }
        return places.firstIndex { q in
            guard Place.fold(q.name) == name else { return false }
            switch (p.coordinate, q.coordinate) {
            case let (a?, b?) where a.isValid && b.isValid: return Geo.distance(a, b) < 120
            case (nil, _), (_, nil): return true
            default: return false
            }
        }
    }

    /// Adds or merges. A saved place always wins over a discovered one (you keep your lists and note).
    @discardableResult
    public mutating func upsert(_ p: Place) -> String {
        guard let i = places.firstIndex(where: { $0.id == p.id }) ?? matchIndex(for: p) else {
            places.append(p)
            return p.id
        }
        merge(at: i, with: p)
        return places[i].id
    }

    /// Bulk version for big imports (thousands of places): indexes once instead of scanning per place.
    /// Returns how many places were new.
    @discardableResult
    public mutating func upsertMany(_ incoming: [Place]) -> Int {
        var byID: [String: Int] = [:]
        var byURL: [String: Int] = [:]
        var byName: [String: [Int]] = [:]
        func index(_ i: Int) {
            let q = places[i]
            byID[q.id] = i
            if let u = q.url, !u.isEmpty { byURL[u] = i }
            byName[Place.fold(q.name), default: []].append(i)
        }
        for i in places.indices { index(i) }
        var added = 0
        for p in incoming {
            var hit = byID[p.id] ?? p.url.flatMap { byURL[$0] }
            if hit == nil {
                hit = byName[Place.fold(p.name)]?.first { i in
                    switch (p.coordinate, places[i].coordinate) {
                    case let (a?, b?) where a.isValid && b.isValid: return Geo.distance(a, b) < 120
                    default: return true
                    }
                }
            }
            if let i = hit {
                merge(at: i, with: p)
            } else {
                places.append(p)
                index(places.count - 1)
                added += 1
            }
        }
        return added
    }

    private mutating func merge(at i: Int, with p: Place) {
        var q = places[i]
        if p.kind == .saved && q.kind != .saved {
            q.kind = .saved
            q.source = p.source
            q.score = 1
        }
        for l in p.lists where !q.lists.contains(l) { q.lists.append(l) }
        if (q.note ?? "").isEmpty, let n = p.note, !n.isEmpty { q.note = n }
        if !q.isResolved, p.isResolved { q.coordinate = p.coordinate }
        q.address = q.address ?? p.address
        q.url = q.url ?? p.url
        q.googlePlaceID = q.googlePlaceID ?? p.googlePlaceID
        q.wikipediaTitle = q.wikipediaTitle ?? p.wikipediaTitle
        q.wikipediaLang = q.wikipediaLang ?? p.wikipediaLang
        q.blurb = q.blurb ?? p.blurb
        q.scenic = q.scenic || p.scenic
        if q.isDiscovered { q.score = max(q.score, p.score) }
        places[i] = q
    }

    public mutating func update(_ p: Place) {
        if let i = places.firstIndex(where: { $0.id == p.id }) { places[i] = p }
    }

    public mutating func remove(id: String) {
        places.removeAll { $0.id == id }
    }

    /// Keeps discovered places bounded: drops ones far from `center` (never saved ones or muted ones,
    /// so a mute survives), then the lowest-scored beyond `maxDiscovered`.
    public mutating func pruneDiscovered(around center: Coordinate, keepWithin meters: Double = 60_000, maxDiscovered: Int = 600) {
        places.removeAll { p in
            guard p.isDiscovered, !p.muted, let c = p.coordinate else { return false }
            return Geo.distance(c, center) > meters
        }
        let disc = places.filter { $0.isDiscovered && !$0.muted }
        guard disc.count > maxDiscovered else { return }
        let drop = Set(disc.sorted { $0.score > $1.score }.dropFirst(maxDiscovered).map(\.id))
        places.removeAll { drop.contains($0.id) }
    }
}

/// JSON file persistence for the library plus an inbox the share extension appends to.
public final class PlaceFileStore {
    public let directory: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public var libraryURL: URL { directory.appendingPathComponent("places.json") }
    public var inboxURL: URL { directory.appendingPathComponent("inbox.json") }

    public func loadLibrary() -> PlaceLibrary {
        guard let data = try? Data(contentsOf: libraryURL),
              let lib = try? decoder.decode(PlaceLibrary.self, from: data) else { return PlaceLibrary() }
        return lib
    }

    public func save(_ lib: PlaceLibrary) {
        guard let data = try? encoder.encode(lib) else { return }
        try? data.write(to: libraryURL, options: .atomic)
    }

    public func appendToInbox(_ p: Place) {
        var items = readInbox()
        items.append(p)
        if let data = try? encoder.encode(items) { try? data.write(to: inboxURL, options: .atomic) }
    }

    public func readInbox() -> [Place] {
        guard let data = try? Data(contentsOf: inboxURL),
              let items = try? decoder.decode([Place].self, from: data) else { return [] }
        return items
    }

    /// Moves inbox items into the library and empties the inbox. Returns ids of the merged places.
    @discardableResult
    public func drainInbox(into lib: inout PlaceLibrary) -> [String] {
        let items = readInbox()
        guard !items.isEmpty else { return [] }
        let ids = items.map { lib.upsert($0) }
        try? FileManager.default.removeItem(at: inboxURL)
        return ids
    }
}
