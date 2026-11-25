import Foundation

/// RFC 4180 CSV: quoted fields, doubled quotes, commas and newlines inside quotes, CRLF or LF.
public enum CSV {
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text.unicodeScalars)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n", "\r":
                    if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default:
                    field.unicodeScalars.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    /// Rows as dictionaries keyed by lowercased header. Blank rows are skipped.
    public static func records(_ text: String) -> [[String: String]] {
        let rows = parse(text)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else { return [] }
        return rows.dropFirst().compactMap { r in
            if r.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { return nil }
            var d: [String: String] = [:]
            for (i, h) in header.enumerated() where i < r.count { d[h] = r[i] }
            return d
        }
    }
}

/// Google Maps links and share-sheet text.
public enum MapsLink {
    private static func firstMatch(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    /// Coordinates embedded in a Google Maps URL. Prefers the place pin (!3d!4d) over the viewport (@lat,lng).
    public static func coordinate(in url: String) -> Coordinate? {
        let s = url.removingPercentEncoding ?? url
        let num = "(-?\\d{1,3}\\.\\d+)"
        let patterns = [
            "!3d\(num)!4d\(num)",
            "[?&](?:q|ll|query|destination|daddr|center)=\(num),\\s*\\+?\(num)",
            "/search/\(num),\\s*\\+?\(num)",
            "/place/\(num),\\s*\\+?\(num)",
            "@\(num),\(num)"
        ]
        for p in patterns {
            if let m = firstMatch(p, in: s), m.count == 3, let lat = Double(m[1]), let lng = Double(m[2]) {
                let c = Coordinate(lat: lat, lng: lng)
                if c.isValid { return c }
            }
        }
        return nil
    }

    /// The place name in a /maps/place/<name>/ URL.
    public static func placeName(in url: String) -> String? {
        guard let m = firstMatch("/maps/place/([^/@?]+)", in: url), m.count == 2 else { return nil }
        let raw = m[1].replacingOccurrences(of: "+", with: " ")
        let name = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespaces)
        if name.isEmpty || coordinate(in: "/place/\(name)") != nil { return nil }
        return name
    }

    /// Search text in a google.com/search?q= or maps ?q= URL when it is not a coordinate.
    public static func queryText(in url: String) -> String? {
        guard let comps = URLComponents(string: url) else { return nil }
        for key in ["q", "query"] {
            if let raw = comps.queryItems?.first(where: { $0.name == key })?.value {
                let v = raw.replacingOccurrences(of: "+", with: " ").trimmingCharacters(in: .whitespaces)
                if !v.isEmpty, coordinate(in: "?q=\(v)") == nil { return v }
            }
        }
        return nil
    }

    /// The continue= target when Google bounces through its cookie consent page (EU).
    public static func unwrapConsent(_ url: String) -> String {
        guard url.contains("consent.google"), let comps = URLComponents(string: url),
              let target = comps.queryItems?.first(where: { $0.name == "continue" })?.value else { return url }
        return target
    }

    public static func isShortLink(_ url: String) -> Bool {
        url.contains("maps.app.goo.gl") || url.contains("goo.gl/maps")
    }

    /// Splits text from the Google Maps share sheet ("Name\nAddress\nhttps://maps.app.goo.gl/...").
    public static func parseShareText(_ text: String) -> (name: String?, address: String?, url: String?) {
        let urlMatch = firstMatch("https?://[^\\s]+", in: text)?.first
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("http") }
        let name = lines.first
        let address = lines.count > 1 ? lines[1] : nil
        return (name, address, urlMatch)
    }
}

/// Google Takeout: "Saved" list CSVs and "Saved Places.json" (GeoJSON, starred places).
public enum Takeout {
    /// One CSV per list. Newer exports have Title, Note, URL, Tags, Comment; older ones Title, Note, URL, Comment.
    public static func parseListCSV(_ text: String, listName: String) -> [Place] {
        CSV.records(text).compactMap { r in
            let url = (r["url"] ?? "").trimmingCharacters(in: .whitespaces)
            var title = (r["title"] ?? "").trimmingCharacters(in: .whitespaces)
            if title.isEmpty { title = MapsLink.placeName(in: url) ?? MapsLink.queryText(in: url) ?? "" }
            guard !title.isEmpty || !url.isEmpty else { return nil }
            let note = [r["note"], r["comment"]].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: " · ")
            return Place(name: title.isEmpty ? "Dropped pin" : title,
                         coordinate: MapsLink.coordinate(in: url),
                         kind: .saved, source: .takeout, lists: [listName],
                         note: note.isEmpty ? nil : note, url: url.isEmpty ? nil : url)
        }
    }

    /// GeoJSON FeatureCollection. Handles the current shape (properties.location.name/address,
    /// google_maps_url) and the older one (properties.Title, properties.Location.Address).
    public static func parseSavedPlacesJSON(_ data: Data, listName: String = "Starred") -> [Place] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return [] }
        return features.compactMap { f in
            let props = f["properties"] as? [String: Any] ?? [:]
            let loc = (props["location"] as? [String: Any]) ?? (props["Location"] as? [String: Any]) ?? [:]
            let url = (props["google_maps_url"] as? String) ?? (props["Google Maps URL"] as? String)
            var coord: Coordinate?
            if let g = f["geometry"] as? [String: Any], let cs = g["coordinates"] as? [Double], cs.count >= 2 {
                let c = Coordinate(lat: cs[1], lng: cs[0])
                if c.isValid { coord = c }
            }
            if coord == nil, let u = url { coord = MapsLink.coordinate(in: u) }
            let name = (loc["name"] as? String) ?? (loc["Business Name"] as? String) ?? (props["Title"] as? String)
                ?? url.flatMap { MapsLink.placeName(in: $0) ?? MapsLink.queryText(in: $0) }
            guard let n = name, !n.isEmpty else {
                guard coord != nil else { return nil }
                return Place(name: "Dropped pin", coordinate: coord, kind: .saved, source: .takeout, lists: [listName], url: url)
            }
            let address = (loc["address"] as? String) ?? (loc["Address"] as? String)
            let comment = (props["Comment"] as? String) ?? (props["comment"] as? String)
            return Place(name: n, coordinate: coord, kind: .saved, source: .takeout, lists: [listName],
                         note: (comment?.isEmpty ?? true) ? nil : comment, address: address, url: url)
        }
    }

    /// List name from a Takeout file name ("Want to go.csv" -> "Want to go").
    public static func listName(fromFileName name: String) -> String {
        var n = name
        if let dot = n.lastIndex(of: ".") { n = String(n[..<dot]) }
        return n.trimmingCharacters(in: .whitespaces)
    }
}
