import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Shared Google Maps lists ("Share" on a list in Google Maps gives a maps.app.goo.gl link).
/// The list page loads its places, with coordinates, from an undocumented endpoint; this reads it.
/// Google can change that format at any time: everything here fails soft (nil or empty), never crashes.
public enum GoogleList {
    /// Marks a share-sheet inbox item that is a list link to import, not a place.
    public static let marker = "__google_list__"

    public static let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// List id from a placelists URL or the data= form Google redirects to.
    public static func listID(in url: String) -> String? {
        let s = url.removingPercentEncoding ?? url
        for pattern in ["placelists/list/([A-Za-z0-9_-]{12,})", "!11m\\d+!2s([A-Za-z0-9_-]{12,})"] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = s as NSString
            if let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }

    public static func dataURL(listID: String, max: Int = 10_000) -> URL {
        URL(string: "https://www.google.com/maps/preview/entitylist/getlist?authuser=0&hl=en&gl=us&pb=!1m4!1s\(listID)!2e1!3m1!1e1!2e2!3e2!4i\(max)!16b1")!
    }

    public static func request(listID: String) -> URLRequest {
        var r = URLRequest(url: dataURL(listID: listID), timeoutInterval: 60)
        r.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        return r
    }

    public struct List: Sendable {
        public var name: String
        public var places: [Place]
    }

    public static func parse(_ data: Data) -> List? {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        if text.hasPrefix(")]}'"), let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any],
              let list = root.first as? [Any], list.count > 8 else { return nil }
        let name = (list[4] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Google Maps list"
        let items = list[8] as? [Any] ?? []
        let places: [Place] = items.compactMap { raw in
            guard let item = raw as? [Any], item.count > 2,
                  let info = item[1] as? [Any], info.count > 5,
                  let title = item[2] as? String, !title.isEmpty else { return nil }
            var coord: Coordinate?
            if let c = info[5] as? [Any], c.count > 3, let lat = c[2] as? Double, let lng = c[3] as? Double {
                let k = Coordinate(lat: lat, lng: lng)
                if k.isValid { coord = k }
            }
            let address = (info[4] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (info[2] as? String)
            let note = (item.count > 3 ? item[3] as? String : nil).flatMap { $0.isEmpty ? nil : $0 }
            var url: String?
            var id = UUID().uuidString
            if info.count > 6, let cid = info[6] as? [Any], cid.count > 1, let s = cid[1] as? String, let v = Int64(s) {
                let u = UInt64(bitPattern: v)
                url = "https://maps.google.com/?cid=\(u)"
                id = "gmap:\(u)"
            }
            return Place(id: id, name: title, coordinate: coord, kind: .saved, source: .share, lists: [name],
                         note: note, address: address, url: url)
        }
        return List(name: name, places: places)
    }
}
