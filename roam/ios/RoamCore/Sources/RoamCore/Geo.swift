import Foundation

public enum MathX {
    public static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
    public static func deg(_ rad: Double) -> Double { rad * 180 / .pi }
    public static func rad(_ deg: Double) -> Double { deg * .pi / 180 }

    /// Wraps an angle to -180...180.
    public static func wrap180(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }
        if x < -180 { x += 360 }
        return x
    }
}

public struct Coordinate: Codable, Hashable, Sendable {
    public var lat: Double
    public var lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }

    /// Rejects (0,0) and out-of-range values, which show up in exports for places without a pin.
    public var isValid: Bool {
        lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 && !(abs(lat) < 0.0001 && abs(lng) < 0.0001)
    }
}

public enum Geo {
    public static let earthRadius = 6_371_000.0

    /// Great-circle distance in meters (haversine).
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = MathX.rad(b.lat - a.lat)
        let dLng = MathX.rad(b.lng - a.lng)
        let la1 = MathX.rad(a.lat)
        let la2 = MathX.rad(b.lat)
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from a to b, degrees clockwise from north.
    public static func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let la1 = MathX.rad(a.lat), la2 = MathX.rad(b.lat)
        let dLng = MathX.rad(b.lng - a.lng)
        let y = sin(dLng) * cos(la2)
        let x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLng)
        var deg = MathX.deg(atan2(y, x))
        if deg < 0 { deg += 360 }
        return deg
    }

    public static func compass(_ bearing: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int(((bearing.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45).rounded(.down)) % 8
        return names[i]
    }

    /// Walking time: 4.8 km/h with a 1.25 street-grid detour factor on the straight-line distance.
    public static func walkingMinutes(_ meters: Double) -> Int {
        max(1, Int((meters * 1.25 / 80).rounded()))
    }

    public static func formatDistance(_ meters: Double, metric: Bool) -> String {
        if metric {
            if meters < 950 { return "\(Int((meters / 10).rounded() * 10)) m" }
            return String(format: "%.1f km", meters / 1000)
        }
        let feet = meters * 3.28084
        if feet < 1000 { return "\(Int((feet / 10).rounded() * 10)) ft" }
        return String(format: "%.1f mi", meters / 1609.344)
    }

    /// Offsets a coordinate by meters north and east (good enough for a few km).
    public static func offset(_ c: Coordinate, north: Double, east: Double) -> Coordinate {
        let dLat = north / earthRadius
        let dLng = east / (earthRadius * cos(MathX.rad(c.lat)))
        return Coordinate(lat: c.lat + MathX.deg(dLat), lng: c.lng + MathX.deg(dLng))
    }
}

/// A coarse lat/lng grid for fast "what is near me" lookups over thousands of points.
public struct GridIndex<T> {
    public let cellDegrees: Double
    private var cells: [Int64: [(Coordinate, T)]] = [:]
    public private(set) var count = 0

    public init(cellDegrees: Double = 0.05) {
        self.cellDegrees = cellDegrees
    }

    private func key(_ row: Int, _ col: Int) -> Int64 { Int64(row) &* 1_000_003 &+ Int64(col) }
    private func cell(_ c: Coordinate) -> (Int, Int) {
        (Int((c.lat / cellDegrees).rounded(.down)), Int((c.lng / cellDegrees).rounded(.down)))
    }

    public mutating func insert(_ value: T, at c: Coordinate) {
        let (r, k) = cell(c)
        cells[key(r, k), default: []].append((c, value))
        count += 1
    }

    /// Items within `radius` meters of `center`, nearest first, with their distances.
    public func query(near center: Coordinate, radius: Double) -> [(value: T, distance: Double)] {
        let latSpan = radius / 111_000
        let lngSpan = radius / max(1, 111_000 * cos(MathX.rad(center.lat)))
        let rowSpan = Int((latSpan / cellDegrees).rounded(.up))
        let colSpan = Int((lngSpan / cellDegrees).rounded(.up))
        let (r0, c0) = cell(center)
        var out: [(value: T, distance: Double)] = []
        for r in (r0 - rowSpan)...(r0 + rowSpan) {
            for c in (c0 - colSpan)...(c0 + colSpan) {
                guard let items = cells[key(r, c)] else { continue }
                for (coord, v) in items {
                    let d = Geo.distance(center, coord)
                    if d <= radius { out.append((v, d)) }
                }
            }
        }
        return out.sorted { $0.distance < $1.distance }
    }
}
