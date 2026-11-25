import Foundation

public enum LightPhase: String, Codable, Sendable {
    case night, blueHour, goldenHour, daylight, harsh

    public var label: String {
        switch self {
        case .night: return "night"
        case .blueHour: return "blue hour"
        case .goldenHour: return "golden hour"
        case .daylight: return "daylight"
        case .harsh: return "harsh sun"
        }
    }

    public static func from(elevation e: Double) -> LightPhase {
        if e < -6 { return .night }
        if e < -4 { return .blueHour }
        if e < 6 { return .goldenHour }
        if e < 45 { return .daylight }
        return .harsh
    }
}

public struct SunPosition: Equatable, Sendable {
    /// Degrees clockwise from true north.
    public var azimuth: Double
    /// Degrees above the horizon (negative below).
    public var elevation: Double
    public var phase: LightPhase { .from(elevation: elevation) }
}

/// NOAA's general solar position equations (accuracy around 0.5 degree), enough to coach light direction.
public enum Sun {
    public static func position(at date: Date, latitude: Double, longitude: Double) -> SunPosition {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.year, .hour, .minute, .second], from: date)
        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let year = comps.year ?? 2000
        let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let daysInYear = isLeap ? 366.0 : 365.0
        let hour = Double(comps.hour ?? 0)
        let minute = Double(comps.minute ?? 0)
        let second = Double(comps.second ?? 0)

        let gamma = 2 * Double.pi / daysInYear * (dayOfYear - 1 + (hour - 12) / 24)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                               - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)

        let timeOffset = eqTime + 4 * longitude
        let tst = hour * 60 + minute + second / 60 + timeOffset
        let haDeg = tst / 4 - 180
        let ha = MathX.rad(haDeg)
        let lat = MathX.rad(latitude)

        let cosZen = MathX.clamp(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha), -1, 1)
        let zenith = acos(cosZen)
        var elevation = 90 - MathX.deg(zenith)
        elevation += refraction(elevation)

        let azFromSouth = atan2(sin(ha), cos(ha) * sin(lat) - tan(decl) * cos(lat))
        var azimuth = MathX.deg(azFromSouth) + 180
        azimuth = azimuth.truncatingRemainder(dividingBy: 360)
        if azimuth < 0 { azimuth += 360 }
        return SunPosition(azimuth: azimuth, elevation: elevation)
    }

    /// Atmospheric refraction near the horizon (Saemundsson), degrees.
    static func refraction(_ h: Double) -> Double {
        guard h > -2 else { return 0 }
        let r = 1.02 / tan(MathX.rad(h + 10.3 / (h + 5.11))) / 60
        return max(0, r)
    }

    /// The next stretch of golden-hour light starting from `date` (or the current one if already in it).
    /// Searches 26 hours ahead in 2-minute steps. nil near the poles when the sun never reaches it.
    public static func goldenWindow(from date: Date, latitude: Double, longitude: Double) -> (start: Date, end: Date)? {
        let step: TimeInterval = 120
        let limit = 26 * 3600 / step
        var start: Date?
        var t = date
        for _ in 0..<Int(limit) {
            let golden = position(at: t, latitude: latitude, longitude: longitude).phase == .goldenHour
            if golden && start == nil { start = t }
            if !golden, let s = start { return (s, t) }
            t = t.addingTimeInterval(step)
        }
        if let s = start { return (s, t) }
        return nil
    }

    /// Sun azimuth relative to where the lens points, -180...180. 0 = lens points into the sun.
    public static func relativeAzimuth(sunAzimuth: Double, lensHeading: Double) -> Double {
        MathX.wrap180(sunAzimuth - lensHeading)
    }
}
