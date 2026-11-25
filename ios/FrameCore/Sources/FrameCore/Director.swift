import Foundation

public enum DirectorModels {
    public static let all = ["gemini-3.8-flash", "gemini-3.6-flash", "gemini-3.1-flash-lite", "gemini-2.5-flash"]
    public static let `default` = all[0]
}

/// Facts about the moment that a single frame cannot show.
public struct DirectorContext: Equatable, Sendable {
    public var mode: ShootMode
    public var side: CameraSide
    public var zoom: Double
    public var elevation: Double
    public var levelError: Double
    public var people: Int
    public var localTime: String
    public var sun: String?
    public var place: String?
    /// When the photo will be taken with another camera, what it is and the planned settings.
    public var camera: String?

    public init(mode: ShootMode, side: CameraSide, zoom: Double, elevation: Double, levelError: Double, people: Int,
                localTime: String, sun: String? = nil, place: String? = nil, camera: String? = nil) {
        self.mode = mode
        self.side = side
        self.zoom = zoom
        self.elevation = elevation
        self.levelError = levelError
        self.people = people
        self.localTime = localTime
        self.sun = sun
        self.place = place
        self.camera = camera
    }

    /// Plain-language description of where the sun is, for the prompt.
    public static func sunPhrase(_ s: SunContext) -> String {
        var parts = ["sun \(Int(s.elevation.rounded()))° above the horizon (\(s.phase.label))"]
        if let rel = s.relativeAzimuth, s.elevation > -4 {
            let a = abs(rel)
            if a < 35 { parts.append("roughly in front of the lens, behind the subject") }
            else if a > 145 { parts.append("behind the photographer, lighting the subject from the front") }
            else { parts.append("to the \(rel > 0 ? "right" : "left") of the lens, side-lighting the subject") }
        }
        return parts.joined(separator: ", ")
    }
}

public struct DirectorMove: Equatable, Codable, Sendable {
    public var who: Who
    public var instruction: String
    public var arrow: Arrow?
}

public struct DirectorAdvice: Equatable, Sendable {
    public var headline: String
    public var rating: Int?
    public var moves: [DirectorMove]
    public var pose: [String]
    public var background: String?
    public var light: String?
    public var lens: Double?
    /// Where the main subject should sit after the changes.
    public var subjectBox: Rect?
    public var idea: String?
    public var cameraTip: String?
}

public enum Director {
    public static func prompt(_ c: DirectorContext) -> String {
        let camera = c.side == .front ? "front (selfie) camera, image is mirrored as the user sees it" : "rear camera"
        let lensLine = c.side == .front ? "fixed selfie lens" : String(format: "%.1fx", c.zoom)
        let who = c.side == .front ? "\"you\" (the person taking the selfie)" : "\"photographer\" or \"subject\""
        var ctx = [
            "Mode: \(c.mode.rawValue)",
            "Camera: \(camera)",
            "Lens: \(lensLine)",
            String(format: "Phone aimed %.0f° %@ the horizon, tilted %.0f° from level", abs(c.elevation), c.elevation >= 0 ? "above" : "below", abs(c.levelError)),
            "People detected: \(c.people)",
            "Local time: \(c.localTime)"
        ]
        if let s = c.sun { ctx.append("Light: \(s)") }
        if let p = c.place { ctx.append("Place: \(p)") }
        if let cam = c.camera { ctx.append("Final camera: \(cam). The iPhone frame shows that camera's field of view.") }
        let cameraRule = c.camera == nil ? "" : """
        - The photo will be taken with the camera named under Final camera, not the iPhone. Lens advice must fit it \
        (no switching iPhone lenses). In camera_tip, say in one sentence whether to change its planned settings and how.

        """

        return """
        You are a world-class travel and portrait photographer standing next to someone with an iPhone, coaching them in real time. \
        The image is their live viewfinder right now. Your job: say exactly what to change so THIS photo becomes excellent.

        Context:
        \(ctx.map { "- " + $0 }.joined(separator: "\n"))

        Think about, in order of impact: camera position and height, angle and distance; what is behind the subject \
        (things growing out of heads, horizons through necks, clutter, bright distractions at the edges); light direction \
        and quality on faces; composition (where the subject sits, leading lines, foreground, framing, headroom, crops at joints); \
        and for people, pose and expression (angles, chin, posture, hands, weight on the back leg, spacing in groups).

        Rules:
        - Be specific and physical, with distances and directions: "Take two steps left so the lamp post leaves her head", \
        not "improve the background". Directions are from the photographer's point of view.
        - Only advise what is visible or follows from the context. Never invent things that are not in the frame.
        - At most 3 moves, the highest impact first. Pose tips only when people are in frame.
        - Keep every string under 110 characters. Plain words, no jargon.
        - who must be \(who).
        - direction is one of: left, right, closer, back, raise, lower, tiltUp, tiltDown, rotateCW, rotateCCW, turn, none.
        \(cameraRule)- subject_box is where the main subject should sit in the frame after your changes, as [ymin, xmin, ymax, xmax] \
        scaled 0 to 1000, or null if the framing is already right.

        Return only JSON:
        {"headline": string, "rating": integer 1-10 for the shot as it is now, \
        "moves": [{"who": string, "do": string, "direction": string}], "pose": [string], \
        "background": string, "light": string, "lens": "0.5" | "1" | "2" | "3" | "5" | "none", \
        "subject_box": [number, number, number, number] | null, "idea": string\(c.camera == nil ? "" : ", \"camera_tip\": string")}
        """
    }

    /// Pulls the first JSON object out of a reply (models sometimes wrap it in fences or prose).
    public static func extractJSONObject(_ s: String) -> [String: Any]? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < s.endIndex {
            let ch = s[i]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else {
                if ch == "\"" { inString = true }
                else if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        let sub = String(s[start...i])
                        guard let d = sub.data(using: .utf8) else { return nil }
                        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
                    }
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    static func str(_ v: Any?) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func num(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "x", with: "")) }
        return nil
    }

    static func arrow(_ v: Any?) -> Arrow? {
        guard let s = str(v)?.lowercased() else { return nil }
        let map: [String: Arrow] = ["left": .left, "right": .right, "closer": .closer, "back": .back, "raise": .raise,
                                    "lower": .lower, "tiltup": .tiltUp, "tiltdown": .tiltDown, "rotatecw": .rotateCW,
                                    "rotateccw": .rotateCCW, "turn": .turn, "up": .up, "down": .down]
        return map[s.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "")]
    }

    static func actor(_ v: Any?, side: CameraSide) -> Who {
        switch str(v)?.lowercased() ?? "" {
        case "subject", "subjects", "them", "model": return .subject
        case "you", "me", "self": return .you
        default: return side == .front ? .you : .photographer
        }
    }

    public static func parse(_ text: String, side: CameraSide) -> DirectorAdvice? {
        guard let o = extractJSONObject(text) else { return nil }
        var moves: [DirectorMove] = []
        if let arr = o["moves"] as? [[String: Any]] {
            for m in arr.prefix(3) {
                guard let instr = str(m["do"]) ?? str(m["instruction"]) else { continue }
                moves.append(DirectorMove(who: actor(m["who"], side: side), instruction: instr, arrow: arrow(m["direction"])))
            }
        }
        let headline = str(o["headline"]) ?? moves.first?.instruction
        guard let headline else { return nil }
        var box: Rect?
        if let b = o["subject_box"] as? [Any], b.count == 4 {
            let v = b.compactMap { num($0) }
            if v.count == 4 {
                let ymin = v[0] / 1000, xmin = v[1] / 1000, ymax = v[2] / 1000, xmax = v[3] / 1000
                if xmax > xmin, ymax > ymin {
                    box = Rect(x: xmin, y: ymin, w: xmax - xmin, h: ymax - ymin).clamped
                    // Mirror for the selfie camera: the model saw the mirrored image, so no change needed.
                }
            }
        }
        var lens: Double?
        if let l = num(o["lens"]), l > 0 { lens = l }
        let rating = num(o["rating"]).map { Int(MathX.clamp($0.rounded(), 1, 10)) }
        let pose = ((o["pose"] as? [Any]) ?? []).compactMap { str($0) }.prefix(3)
        return DirectorAdvice(headline: headline, rating: rating, moves: moves, pose: Array(pose),
                              background: str(o["background"]), light: str(o["light"]), lens: lens,
                              subjectBox: box, idea: str(o["idea"]), cameraTip: str(o["camera_tip"]))
    }
}
