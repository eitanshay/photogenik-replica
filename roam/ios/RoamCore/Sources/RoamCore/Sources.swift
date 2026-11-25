import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Request builders and response parsers for every outside source. Networking itself lives in the app;
// keeping the parsing here means it is unit-tested against real response shapes.

private func json(_ data: Data) -> Any? { try? JSONSerialization.jsonObject(with: data) }

private func formEncode(_ s: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
}

// MARK: - Wikipedia (discovery and audio-guide source text)

public struct WikiPage: Hashable, Sendable {
    public var title: String
    public var coordinate: Coordinate
    public var length: Int
    public var description: String?
}

public enum Wikipedia {
    public static func nearbyURL(_ c: Coordinate, lang: String = "en", radius: Int = 10_000, limit: Int = 50) -> URL {
        var comps = URLComponents(string: "https://\(lang).wikipedia.org/w/api.php")!
        comps.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"), .init(name: "formatversion", value: "2"),
            .init(name: "generator", value: "geosearch"),
            .init(name: "ggscoord", value: String(format: "%.6f|%.6f", c.lat, c.lng)),
            .init(name: "ggsradius", value: String(min(10_000, radius))), .init(name: "ggslimit", value: String(limit)),
            .init(name: "prop", value: "coordinates|info|description")
        ]
        return comps.url!
    }

    public static func parseNearby(_ data: Data) -> [WikiPage] {
        guard let root = json(data) as? [String: Any], let q = root["query"] as? [String: Any],
              let pages = q["pages"] as? [[String: Any]] else { return [] }
        return pages.compactMap { p in
            guard let title = p["title"] as? String,
                  let coords = p["coordinates"] as? [[String: Any]], let c0 = coords.first,
                  let lat = c0["lat"] as? Double, let lon = c0["lon"] as? Double else { return nil }
            return WikiPage(title: title, coordinate: Coordinate(lat: lat, lng: lon),
                            length: p["length"] as? Int ?? 0, description: p["description"] as? String)
        }
    }

    static let boring = ["street", "road", "avenue", "boulevard", "highway", "railway station", "metro station",
                         "subway station", "train station", "bus station", "tram stop", "school", "college", "university campus",
                         "neighbourhood", "neighborhood", "district", "village", "municipality", "human settlement",
                         "suburb", "census", "hotel", "company", "business", "constituency", "electoral", "ward of",
                         "hospital", "office building", "embassy", "consulate", "residential", "apartment", "shopping",
                         "headquarters", "radio station", "television", "airport", "parish of", "county", "city in",
                         "town in", "commune in", "capital of", "region of", "province of", "state of"]

    /// Notable sights only: long articles, no streets, stations, districts or towns.
    public static func discoveries(_ pages: [WikiPage], lang: String = "en", minLength: Int = 7_000) -> [Place] {
        pages.compactMap { p in
            guard p.length >= minLength, !p.title.hasPrefix("List of") else { return nil }
            let d = (p.description ?? "").lowercased()
            if boring.contains(where: { d.contains($0) }) { return nil }
            let score = MathX.clamp((log10(Double(p.length)) - 3.8) / 1.2, 0.05, 1)
            let scenicWords = ["viewpoint", "waterfall", "lighthouse", "bridge", "garden", "beach", "lake", "cliff", "mountain", "park", "palace", "castle", "cathedral"]
            return Place(id: "wiki:\(lang):\(p.title)", name: p.title, coordinate: p.coordinate, kind: .attraction,
                         source: .wikipedia, url: "https://\(lang).wikipedia.org/wiki/\(p.title.replacingOccurrences(of: " ", with: "_"))",
                         wikipediaTitle: p.title, wikipediaLang: lang, blurb: p.description,
                         scenic: scenicWords.contains { d.contains($0) }, score: score)
        }
    }

    public static func extractURL(title: String, lang: String = "en") -> URL {
        var comps = URLComponents(string: "https://\(lang).wikipedia.org/w/api.php")!
        comps.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"), .init(name: "formatversion", value: "2"),
            .init(name: "prop", value: "extracts"), .init(name: "explaintext", value: "1"), .init(name: "redirects", value: "1"),
            .init(name: "titles", value: title)
        ]
        return comps.url!
    }

    /// Plain-text article, cut at section headings that rarely help a listener and capped at `maxChars`.
    public static func parseExtract(_ data: Data, maxChars: Int = 7_000) -> String? {
        guard let root = json(data) as? [String: Any], let q = root["query"] as? [String: Any],
              let pages = q["pages"] as? [[String: Any]], let text = pages.first?["extract"] as? String,
              !text.isEmpty else { return nil }
        var t = text
        for stop in ["\n== See also", "\n== References", "\n== Notes", "\n== External links", "\n== Further reading", "\n== Bibliography"] {
            if let r = t.range(of: stop) { t = String(t[..<r.lowerBound]) }
        }
        t = t.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        return String(t.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxChars))
    }

    /// Search for an article about a named place (used when a saved place has no Wikipedia link).
    public static func searchURL(_ query: String, lang: String = "en") -> URL {
        var comps = URLComponents(string: "https://\(lang).wikipedia.org/w/api.php")!
        comps.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"), .init(name: "formatversion", value: "2"),
            .init(name: "list", value: "search"), .init(name: "srsearch", value: query), .init(name: "srlimit", value: "3")
        ]
        return comps.url!
    }

    public static func parseSearch(_ data: Data) -> [String] {
        guard let root = json(data) as? [String: Any], let q = root["query"] as? [String: Any],
              let items = q["search"] as? [[String: Any]] else { return [] }
        return items.compactMap { $0["title"] as? String }
    }
}

// MARK: - OpenStreetMap via Overpass (restrooms, scenic spots)

public enum Overpass {
    public static let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    public static func request(_ query: String) -> URLRequest {
        var r = URLRequest(url: endpoint, timeoutInterval: 25)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data(("data=" + formEncode(query)).utf8)
        return r
    }

    public static func restroomQuery(_ c: Coordinate, radius: Int = 1_000) -> String {
        let a = String(format: "around:%d,%.6f,%.6f", radius, c.lat, c.lng)
        return "[out:json][timeout:20];(node[\"amenity\"=\"toilets\"](\(a));way[\"amenity\"=\"toilets\"](\(a)););out center 80;"
    }

    public static func scenicQuery(_ c: Coordinate, radius: Int = 8_000) -> String {
        let a = String(format: "around:%d,%.6f,%.6f", radius, c.lat, c.lng)
        let parts = [
            "nwr[\"tourism\"=\"viewpoint\"](\(a));",
            "node[\"waterway\"=\"waterfall\"][\"name\"](\(a));",
            "nwr[\"man_made\"=\"lighthouse\"](\(a));",
            "node[\"natural\"=\"peak\"][\"name\"][\"wikidata\"](\(a));",
            "way[\"natural\"=\"beach\"][\"name\"](\(a));",
            "nwr[\"leisure\"=\"garden\"][\"name\"][\"wikidata\"](\(a));",
            "nwr[\"tourism\"=\"attraction\"][\"wikidata\"](\(a));"
        ]
        return "[out:json][timeout:25];(" + parts.joined() + ");out center 250;"
    }

    public struct Element: Hashable, Sendable {
        public var id: String
        public var coordinate: Coordinate
        public var tags: [String: String]
    }

    public static func parse(_ data: Data) -> [Element] {
        guard let root = json(data) as? [String: Any], let els = root["elements"] as? [[String: Any]] else { return [] }
        return els.compactMap { e in
            let type = e["type"] as? String ?? "node"
            let idv = (e["id"] as? Int).map(String.init) ?? "\(e["id"] ?? "")"
            var lat = e["lat"] as? Double, lon = e["lon"] as? Double
            if lat == nil, let center = e["center"] as? [String: Any] {
                lat = center["lat"] as? Double
                lon = center["lon"] as? Double
            }
            guard let la = lat, let lo = lon else { return nil }
            return Element(id: "osm:\(type)/\(idv)", coordinate: Coordinate(lat: la, lng: lo), tags: e["tags"] as? [String: String] ?? [:])
        }
    }

    public static func restrooms(_ els: [Element]) -> [Venue] {
        els.map { e in
            Venue(id: e.id, name: e.tags["name"] ?? "Public restroom", coordinate: e.coordinate, source: .osm,
                  tags: e.tags.filter { ["fee", "access", "wheelchair", "unisex", "opening_hours"].contains($0.key) })
        }
    }

    /// Scenic spots with a 0...1 score by type. Unnamed viewpoints are kept (often the best ones) but rank lower.
    public static func scenicPlaces(_ els: [Element]) -> [Place] {
        var out: [Place] = []
        for e in els {
            let t = e.tags
            var base: Double
            var kindName: String
            if t["tourism"] == "viewpoint" { base = 0.75; kindName = "Viewpoint" }
            else if t["waterway"] == "waterfall" { base = 0.75; kindName = "Waterfall" }
            else if t["man_made"] == "lighthouse" { base = 0.65; kindName = "Lighthouse" }
            else if t["natural"] == "peak" { base = 0.55; kindName = "Peak" }
            else if t["natural"] == "beach" { base = 0.55; kindName = "Beach" }
            else if t["leisure"] == "garden" { base = 0.55; kindName = "Garden" }
            else if t["tourism"] == "attraction" { base = 0.5; kindName = "Attraction" }
            else { continue }
            let name = t["name:en"] ?? t["name"]
            if t["wikidata"] != nil || t["wikipedia"] != nil { base += 0.2 }
            if name == nil { base -= 0.25 }
            if out.contains(where: { Geo.distance($0.coordinate!, e.coordinate) < 60 }) { continue }
            var wikiTitle: String?, wikiLang: String?
            if let w = t["wikipedia"], let colon = w.firstIndex(of: ":") {
                wikiLang = String(w[..<colon])
                wikiTitle = String(w[w.index(after: colon)...])
            }
            out.append(Place(id: e.id, name: name ?? kindName, coordinate: e.coordinate, kind: .scenic, source: .osm,
                             url: "https://www.openstreetmap.org/\(e.id.replacingOccurrences(of: "osm:", with: ""))",
                             wikipediaTitle: wikiTitle, wikipediaLang: wikiLang,
                             blurb: kindName.lowercased(), scenic: true, score: MathX.clamp(base, 0.05, 1)))
        }
        return out
    }
}

// MARK: - Refuge Restrooms (US and some other countries)

public enum Refuge {
    public static func url(_ c: Coordinate) -> URL {
        URL(string: String(format: "https://www.refugerestrooms.org/api/v1/restrooms/by_location?lat=%.6f&lng=%.6f&per_page=20", c.lat, c.lng))!
    }

    public static func parse(_ data: Data) -> [Venue] {
        guard let items = json(data) as? [[String: Any]] else { return [] }
        return items.compactMap { r in
            guard let lat = (r["latitude"] as? Double) ?? Double("\(r["latitude"] ?? "")"),
                  let lng = (r["longitude"] as? Double) ?? Double("\(r["longitude"] ?? "")") else { return nil }
            let id = "refuge:\(r["id"] ?? "\(lat),\(lng)")"
            var tags: [String: String] = [:]
            if r["accessible"] as? Bool == true { tags["wheelchair"] = "yes" }
            if r["unisex"] as? Bool == true { tags["unisex"] = "yes" }
            return Venue(id: id, name: r["name"] as? String ?? "Restroom", coordinate: Coordinate(lat: lat, lng: lng),
                         source: .refuge, address: r["street"] as? String, tags: tags)
        }
    }
}

// MARK: - Google Places API (New)

public enum GooglePlaces {
    public static let fieldMask = "places.id,places.displayName,places.location,places.rating,places.userRatingCount,places.priceLevel,places.types,places.currentOpeningHours.openNow,places.formattedAddress,places.googleMapsUri,places.businessStatus"

    private static func request(_ path: String, key: String, body: [String: Any]) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://places.googleapis.com/v1/\(path)")!, timeoutInterval: 15)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        r.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return r
    }

    private static func circle(_ c: Coordinate, _ radius: Double) -> [String: Any] {
        ["circle": ["center": ["latitude": c.lat, "longitude": c.lng], "radius": min(50_000, radius)]]
    }

    public static func nearby(types: [String], at c: Coordinate, radius: Double, key: String, max: Int = 20) -> URLRequest {
        request("places:searchNearby", key: key, body: [
            "includedTypes": types, "maxResultCount": max, "rankPreference": "POPULARITY",
            "locationRestriction": circle(c, radius)
        ])
    }

    public static func text(_ query: String, near c: Coordinate?, radius: Double = 2_000, key: String, max: Int = 20, openNow: Bool = false) -> URLRequest {
        var body: [String: Any] = ["textQuery": query, "pageSize": max]
        if let c = c { body["locationBias"] = circle(c, radius) }
        if openNow { body["openNow"] = true }
        return request("places:searchText", key: key, body: body)
    }

    public static func priceLevel(_ s: String?) -> Int? {
        switch s {
        case "PRICE_LEVEL_FREE", "PRICE_LEVEL_INEXPENSIVE": return 1
        case "PRICE_LEVEL_MODERATE": return 2
        case "PRICE_LEVEL_EXPENSIVE": return 3
        case "PRICE_LEVEL_VERY_EXPENSIVE": return 4
        default: return nil
        }
    }

    /// Parses a searchNearby/searchText response. Closed-for-good places are dropped.
    /// Throws with Google's message when the response is an error (bad key, API not enabled, billing).
    public static func parse(_ data: Data) throws -> [Venue] {
        guard let root = json(data) as? [String: Any] else { return [] }
        if let err = root["error"] as? [String: Any] {
            throw SourceError.api(err["message"] as? String ?? "Google Places error")
        }
        let places = root["places"] as? [[String: Any]] ?? []
        return places.compactMap { p in
            guard let id = p["id"] as? String, let loc = p["location"] as? [String: Any],
                  let lat = loc["latitude"] as? Double, let lng = loc["longitude"] as? Double else { return nil }
            if let s = p["businessStatus"] as? String, s == "CLOSED_PERMANENTLY" || s == "CLOSED_TEMPORARILY" { return nil }
            let name = (p["displayName"] as? [String: Any])?["text"] as? String ?? "Place"
            let open = (p["currentOpeningHours"] as? [String: Any])?["openNow"] as? Bool
            return Venue(id: "g:\(id)", name: name, coordinate: Coordinate(lat: lat, lng: lng), source: .google,
                         rating: p["rating"] as? Double, ratingCount: p["userRatingCount"] as? Int,
                         priceLevel: priceLevel(p["priceLevel"] as? String), types: p["types"] as? [String] ?? [],
                         openNow: open, address: p["formattedAddress"] as? String, mapsURL: p["googleMapsUri"] as? String)
        }
    }
}

public enum SourceError: Error, Equatable, LocalizedError {
    case api(String)
    case missingKey(String)

    public var errorDescription: String? {
        switch self {
        case .api(let m): return m
        case .missingKey(let what): return "Add your \(what) in Settings."
        }
    }
}

// MARK: - Claude (audio-guide scripts, trip-doc extraction)

public enum Claude {
    public static let defaultModel = "claude-opus-5-5"

    public static func request(model: String, key: String, system: String, user: String, maxTokens: Int = 1_200) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 90)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model, "max_tokens": maxTokens, "system": system,
            "messages": [["role": "user", "content": user]]
        ]
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return r
    }

    public static func parseText(_ data: Data) throws -> String {
        guard let root = json(data) as? [String: Any] else { throw SourceError.api("Unreadable reply from Claude") }
        if let err = root["error"] as? [String: Any] {
            throw SourceError.api(err["message"] as? String ?? "Claude error")
        }
        let blocks = root["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        guard !text.isEmpty else { throw SourceError.api("Empty reply from Claude") }
        return text
    }
}

// MARK: - Google Drive (trip docs)

public struct DriveFile: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var modified: String?
    public var link: String?
}

public enum Drive {
    public static let scope = "https://www.googleapis.com/auth/drive.readonly"

    public static func searchURL(_ text: String, limit: Int = 15) -> URL {
        let safe = text.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "'", with: "\\'")
        let q = "mimeType='application/vnd.google-apps.document' and trashed=false and fullText contains '\(safe)'"
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [
            .init(name: "q", value: q), .init(name: "pageSize", value: String(limit)),
            .init(name: "orderBy", value: "modifiedTime desc"),
            .init(name: "fields", value: "files(id,name,modifiedTime,webViewLink)")
        ]
        return comps.url!
    }

    public static func exportURL(fileID: String) -> URL {
        URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)/export?mimeType=text/plain")!
    }

    public static func parseFiles(_ data: Data) throws -> [DriveFile] {
        guard let root = json(data) as? [String: Any] else { return [] }
        if let err = root["error"] as? [String: Any] { throw SourceError.api(err["message"] as? String ?? "Drive error") }
        return (root["files"] as? [[String: Any]] ?? []).compactMap { f in
            guard let id = f["id"] as? String, let name = f["name"] as? String else { return nil }
            return DriveFile(id: id, name: name, modified: f["modifiedTime"] as? String, link: f["webViewLink"] as? String)
        }
    }
}

// MARK: - Google OAuth for an installed iOS app (PKCE, no client secret)

public enum GoogleOAuth {
    /// "1234-abc.apps.googleusercontent.com" -> "com.googleusercontent.apps.1234-abc"
    public static func redirectScheme(clientID: String) -> String {
        let parts = clientID.trimmingCharacters(in: .whitespaces).components(separatedBy: ".")
        return parts.reversed().joined(separator: ".")
    }

    public static func redirectURI(clientID: String) -> String { redirectScheme(clientID: clientID) + ":/oauth2redirect" }

    public static func authURL(clientID: String, challenge: String, scope: String = Drive.scope) -> URL {
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirectURI(clientID: clientID)),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent")
        ]
        return comps.url!
    }

    public static func code(fromCallback url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value
    }

    public static func tokenRequest(_ params: [String: String]) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data(params.sorted { $0.key < $1.key }.map { "\($0.key)=\(formEncode($0.value))" }.joined(separator: "&").utf8)
        return r
    }

    public struct Tokens: Equatable, Sendable {
        public var access: String
        public var refresh: String?
        public var expiresIn: Double
    }

    public static func parseTokens(_ data: Data) throws -> Tokens {
        guard let root = json(data) as? [String: Any] else { throw SourceError.api("Unreadable token reply") }
        if let e = root["error"] as? String {
            throw SourceError.api((root["error_description"] as? String) ?? e)
        }
        guard let a = root["access_token"] as? String else { throw SourceError.api("No access token") }
        return Tokens(access: a, refresh: root["refresh_token"] as? String, expiresIn: root["expires_in"] as? Double ?? 3_600)
    }

    /// base64url without padding (RFC 7636).
    public static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
