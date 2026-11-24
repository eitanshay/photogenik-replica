import Foundation

/// How much a cue matters. Fix = the photo will look wrong; improve = clearly better; nice = polish.
public enum Severity: Int, Comparable, Codable, Sendable {
    case fix = 0, improve = 1, nice = 2
    public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }

    var penalty: Int {
        switch self {
        case .fix: return 34
        case .improve: return 14
        case .nice: return 3
        }
    }
}

/// Who has to act on the cue.
public enum Who: String, Codable, Sendable {
    case you, subject, photographer
    public var label: String {
        switch self {
        case .you: return "you"
        case .subject: return "subject"
        case .photographer: return "camera"
        }
    }
}

/// Visual hint drawn on the viewfinder. Phone movements are from the holder's point of view.
public enum Arrow: String, Codable, Sendable {
    case left, right, up, down
    case closer, back
    case raise, lower
    case tiltUp, tiltDown
    case rotateCW, rotateCCW
    case turn
}

/// A one-tap fix the app can apply for the user.
public enum CueAction: Equatable, Codable, Sendable {
    case exposeFace
    case lens(Double)
}

public enum CueID: String, Codable, Sendable {
    case noFace, noSubject
    case phoneLow, phoneSlightlyLow, phoneTooHigh
    case tooClose, tooFar
    case headTilt, faceTurn, faceTurnedAway, chinUp, chinDown
    case eyesLow, headCut, offCenter
    case backlit, faceDark, faceBright, hardSideLight, harshSun, sunBehind
    case mergerVertical, mergerHorizontal, clutter
    case level, shootDownOnBody, shootUpOnFace
    case kneeCrop, feetCrop, limbCrop, headroom
    case useTele, avoidUltraWide
    case squareShoulders, armsGlued, subjectChinUp, subjectChinDown
    case edgePerson, gaps, hiddenFace, flatHeads, groupHeight
    case verticals, skyBlown, lowLight, thirds, intoSun
}

public struct Cue: Identifiable, Equatable, Sendable {
    public var id: CueID
    public var severity: Severity
    public var actor: Who
    /// Short imperative, about 30 characters, shown large.
    public var text: String
    /// One sentence on why, shown smaller.
    public var detail: String?
    public var arrow: Arrow?
    public var action: CueAction?
    /// Points on the frame to mark (joints cut by the edge, etc.).
    public var marks: [Vec2]
    /// Areas on the frame to outline (background collisions).
    public var zones: [Rect]

    public init(_ id: CueID, _ severity: Severity, _ actor: Who, _ text: String, detail: String? = nil,
                arrow: Arrow? = nil, action: CueAction? = nil, marks: [Vec2] = [], zones: [Rect] = []) {
        self.id = id
        self.severity = severity
        self.actor = actor
        self.text = text
        self.detail = detail
        self.arrow = arrow
        self.action = action
        self.marks = marks
        self.zones = zones
    }

    /// What voice coaching says.
    public var spoken: String { text }
}

public enum PreferredSide: String, CaseIterable, Codable, Identifiable, Sendable {
    case either, left, right
    public var id: String { rawValue }
}

public struct CoachSettings: Equatable, Sendable {
    public var mode: ShootMode
    public var preferredSide: PreferredSide
    public init(mode: ShootMode = .auto, preferredSide: PreferredSide = .either) {
        self.mode = mode
        self.preferredSide = preferredSide
    }
}

public struct CoachOutput: Equatable, Sendable {
    public var mode: ShootMode
    /// Sorted: most important first.
    public var cues: [Cue]
    /// 0...100.
    public var readiness: Int
    public var isReady: Bool
    public var eyesClosed: Bool
    /// Tilt from level in degrees when it matters for this shot (drives the level bar).
    public var levelError: Double?
    /// Where the main face or subject should sit.
    public var targetZone: Rect?

    public var primary: Cue? { cues.first }
}

public enum Coach {
    public static func resolveMode(_ a: FrameAnalysis, requested: ShootMode) -> ShootMode {
        if requested != .auto { return requested }
        let n = a.subjectFaces.count
        if a.side == .front { return n >= 3 ? .group : .selfie }
        if n == 0 { return a.bodies.isEmpty ? .scene : .portrait }
        return n >= 3 ? .group : .portrait
    }

    public static func evaluate(_ a: FrameAnalysis, settings: CoachSettings = CoachSettings()) -> CoachOutput {
        let mode = resolveMode(a, requested: settings.mode)
        var cues: [Cue] = []
        var target: Rect?
        var level: Double?

        switch mode {
        case .selfie, .auto:
            cues += selfie(a, settings: settings, target: &target)
        case .portrait:
            level = levelError(a, threshold: 2.5).map { $0.error }
            cues += portrait(a, target: &target)
        case .group:
            level = levelError(a, threshold: 2.5).map { $0.error }
            cues += group(a)
        case .scene:
            level = levelError(a, threshold: 1.5).map { $0.error }
            cues += scene(a, target: &target)
        }

        // Keep one cue per id, most severe first, stable within a severity by the order rules ran in.
        var seen = Set<CueID>()
        cues = cues.enumerated()
            .sorted { $0.element.severity == $1.element.severity ? $0.offset < $1.offset : $0.element.severity < $1.element.severity }
            .map(\.element)
            .filter { seen.insert($0.id).inserted }

        let subjects = a.subjectFaces
        let eyesClosed = subjects.contains { $0.eyesClosed == true }
        var score = 100 - cues.reduce(0) { $0 + $1.severity.penalty }
        if eyesClosed { score -= 45 }
        if (mode == .selfie && a.faces.isEmpty) { score = 0 }
        score = max(0, min(100, score))
        let ready = score >= 78 && !cues.contains { $0.severity == .fix } && !eyesClosed

        return CoachOutput(mode: mode, cues: cues, readiness: score, isReady: ready, eyesClosed: eyesClosed,
                           levelError: level, targetZone: target)
    }

    // MARK: - Shared rules

    /// Tilt from level: the detected horizon when there is one, else the phone's own roll.
    static func levelError(_ a: FrameAnalysis, threshold: Double) -> (error: Double, off: Bool)? {
        guard a.side == .back else { return nil }
        if let h = a.scene.horizonAngle, abs(h) < 20 {
            return (h, abs(h) > threshold)
        }
        guard !a.attitude.isFlat else { return nil }
        let e = a.attitude.levelError
        return (e, abs(e) > threshold)
    }

    static func levelCue(_ a: FrameAnalysis, threshold: Double) -> Cue? {
        guard let l = levelError(a, threshold: threshold), l.off else { return nil }
        let sev: Severity = abs(l.error) > 6 ? .fix : .improve
        return Cue(.level, sev, .photographer, "Level the phone",
                   detail: String(format: "It is %.0f° off. Straight horizons look deliberate.", abs(l.error)),
                   arrow: l.error > 0 ? .rotateCCW : .rotateCW)
    }

    static func lighting(_ a: FrameAnalysis, face: FaceInfo, actor: Who) -> [Cue] {
        var out: [Cue] = []
        let selfie = actor == .you
        guard let fl = face.faceLuma else { return out }
        let sun = a.sun
        let sunBehind = sun.map { s in
            guard let rel = s.relativeAzimuth else { return false }
            return abs(rel) < 45 && s.elevation > -2 && s.elevation < 35
        } ?? false

        if let bg = a.scene.backgroundLuma, bg - fl > 0.22, fl < 0.5 {
            if sunBehind && !selfie {
                out.append(Cue(.sunBehind, .improve, .photographer, "Expose for their face",
                               detail: "The sun is behind them. That rim light is lovely once the face is bright enough.",
                               action: .exposeFace))
            } else {
                out.append(Cue(.backlit, .improve, selfie ? .you : .photographer,
                               selfie ? "Turn to face the light" : "They are backlit",
                               detail: selfie ? "The background is brighter than your face. Turn until light falls on your face."
                                              : "Tap to expose for the face, or turn them so the light falls on their face.",
                               arrow: selfie ? .turn : nil, action: selfie ? .exposeFace : .exposeFace))
            }
        } else if fl < 0.22 {
            out.append(Cue(.faceDark, .improve, selfie ? .you : .subject,
                           selfie ? "Turn toward the light" : "Their face is in shadow",
                           detail: selfie ? "Face a window or the brightest part of the room." : "Turn them toward the light, or expose for the face.",
                           arrow: .turn, action: .exposeFace))
        } else if fl > 0.86 && a.scene.highlightClip > 0.04 {
            out.append(Cue(.faceBright, .improve, .photographer, "The face is too bright",
                           detail: "Expose for the face so skin keeps its detail.", action: .exposeFace))
        }

        if let l = face.lumaLeft, let r = face.lumaRight, min(l, r) > 0.03 {
            let ratio = max(l, r) / min(l, r)
            if ratio > 2.3 {
                if sun?.phase == .harsh && fl > 0.4 {
                    out.append(Cue(.harshSun, .improve, selfie ? .you : .subject, "Find open shade",
                                   detail: "Midday sun carves hard shadows. The edge of a building's shade gives soft, even light."))
                } else {
                    out.append(Cue(.hardSideLight, .nice, selfie ? .you : .subject,
                                   selfie ? "Turn a little toward the light" : "Turn them a little toward the light",
                                   detail: "Half the face is in deep shadow. A small turn fills it in.", arrow: .turn))
                }
            }
        }
        return out
    }

    static func mergerCues(_ a: FrameAnalysis, selfie: Bool) -> [Cue] {
        var out: [Cue] = []
        for m in a.scene.mergers {
            switch m.kind {
            case .vertical:
                if selfie {
                    out.append(Cue(.mergerVertical, .improve, .you, "Something is behind your head",
                                   detail: "A pole or edge rises out of your head. Turn a little so it moves aside.",
                                   arrow: .turn, zones: [m.zone]))
                } else {
                    let arrow: Arrow? = m.calmerSide < 0 ? .right : (m.calmerSide > 0 ? .left : nil)
                    let move = m.calmerSide < 0 ? "Step right a little" : (m.calmerSide > 0 ? "Step left a little" : "Shift sideways a little")
                    out.append(Cue(.mergerVertical, .improve, .photographer, move,
                                   detail: "Something is growing out of their head. A small step moves it aside.",
                                   arrow: arrow, zones: [m.zone]))
                }
            case .horizontal:
                out.append(Cue(.mergerHorizontal, .improve, selfie ? .you : .photographer,
                               selfie ? "A line cuts through your head" : "Lower the phone a little",
                               detail: selfie ? "Raise or lower the phone so the line sits below your shoulders."
                                              : "The horizon slices through their head. From lower, their head rises above it.",
                               arrow: selfie ? .raise : .lower, zones: [m.zone]))
            }
        }
        return out
    }

    // MARK: - Selfie

    static func selfie(_ a: FrameAnalysis, settings: CoachSettings, target: inout Rect?) -> [Cue] {
        guard let face = a.facesBySize.first else {
            return [Cue(.noFace, .fix, .you, "Get your face in the frame")]
        }
        var out: [Cue] = []
        let att = a.attitude

        // Camera height: the single biggest selfie lever.
        if att.elevation > 6 {
            out.append(Cue(.phoneLow, .fix, .you, "Raise the phone above eye level",
                           detail: "Shooting from below adds a chin. Hold it higher and tilt it down toward you.", arrow: .raise))
        } else if att.elevation > -3 {
            out.append(Cue(.phoneSlightlyLow, .nice, .you, "Lift the phone a touch higher",
                           detail: "Slightly above eye level, angled down, is the most flattering selfie height.", arrow: .raise))
        } else if att.elevation < -40 {
            out.append(Cue(.phoneTooHigh, .improve, .you, "Lower the phone a little",
                           detail: "From that high your head looks big and your body small.", arrow: .lower))
        }

        // Distance: the front lens is wide, so too close enlarges the nose.
        if face.rect.w > 0.52 {
            out.append(Cue(.tooClose, .fix, .you, "Hold the phone farther away",
                           detail: "This close, the wide selfie lens enlarges your nose. Extend your arm.", arrow: .back))
        } else if face.rect.w < 0.13 && a.subjectFaces.count == 1 {
            out.append(Cue(.tooFar, .nice, .you, "Bring the phone a bit closer", arrow: .closer))
        }

        // Framing.
        if face.headTop < 0.0 {
            out.append(Cue(.headCut, .improve, .you, "Move the phone up a little",
                           detail: "The top of your head is cut off.", arrow: .up))
        } else if face.eyeY > 0.55 {
            out.append(Cue(.eyesLow, .improve, .you, "Move the phone down a little",
                           detail: "Put your eyes on the upper third of the frame.", arrow: .down))
        }
        if face.rect.midX < 0.2 || face.rect.midX > 0.8 {
            out.append(Cue(.offCenter, .improve, .you, "Center yourself",
                           arrow: face.rect.midX < 0.5 ? .right : .left))
        }

        // Head pose.
        if let roll = face.roll, abs(roll) > 14 {
            out.append(Cue(.headTilt, .improve, .you, "Straighten your head a little",
                           detail: "A slight tilt is fine. A strong one reads as off-balance."))
        }
        if let yaw = face.yaw {
            if abs(yaw) > 35 {
                out.append(Cue(.faceTurnedAway, .improve, .you, "Turn back toward the camera", arrow: .turn))
            } else if abs(yaw) < 5 {
                let side: String
                switch settings.preferredSide {
                case .either: side = "Turn your face slightly to one side"
                case .left: side = "Show a bit more of your left side"
                case .right: side = "Show a bit more of your right side"
                }
                out.append(Cue(.faceTurn, .nice, .you, side,
                               detail: "A slight three-quarter angle shapes the face better than straight on.", arrow: .turn))
            }
        }
        if let r = face.noseRatio {
            if r < 0.40 {
                out.append(Cue(.chinUp, .improve, .you, "Lower your chin a touch",
                               detail: "Chin forward and slightly down defines the jawline."))
            } else if r > 0.80 {
                out.append(Cue(.chinDown, .improve, .you, "Lift your chin slightly",
                               detail: "Bring the chin forward and up a little, as if leading with it."))
            }
        }

        out += lighting(a, face: face, actor: .you)
        out += mergerCues(a, selfie: true)
        if a.scene.clutter > 0.34 {
            out.append(Cue(.clutter, .nice, .you, "Find a calmer background",
                           detail: "A plain wall, sky or foliage keeps the attention on you."))
        }

        target = Rect(x: 0.28, y: 0.18, w: 0.44, h: 0.34)
        return out
    }

    // MARK: - Portrait (one or two people, rear camera)

    static func portrait(_ a: FrameAnalysis, target: inout Rect?) -> [Cue] {
        var out: [Cue] = []
        if let c = levelCue(a, threshold: 2.5) { out.append(c) }
        let faces = a.subjectFaces
        let body = a.mainBody
        guard let face = a.facesBySize.first else {
            if body == nil {
                out.append(Cue(.noSubject, .fix, .photographer, "Point at your subject"))
            }
            return out + bodyCrops(a, body: body)
        }
        let att = a.attitude

        // Framing and crops.
        if face.headTop < 0.005 {
            out.append(Cue(.headCut, .fix, .photographer, "Their head is cut off",
                           detail: "Step back, or aim up a little.", arrow: .back))
        }
        out += bodyCrops(a, body: body)
        let fullBody = body.map { $0[.leftAnkle] != nil || $0[.rightAnkle] != nil } ?? false

        // Camera height.
        if fullBody && att.elevation < -10 && !att.isFlat {
            out.append(Cue(.shootDownOnBody, .improve, .photographer, "Lower the phone to waist height",
                           detail: "Shooting down shortens legs. From waist height, held level, people look taller.", arrow: .lower))
        } else if face.rect.w > 0.12 && att.elevation > 12 && !att.isFlat {
            out.append(Cue(.shootUpOnFace, .improve, .photographer, "Raise the phone to their eye level",
                           detail: "Looking up at a face adds a chin and shows nostrils.", arrow: .raise))
        }

        // Headroom.
        if !fullBody && face.rect.w > 0.16 && face.eyeY > 0.5 {
            out.append(Cue(.eyesLow, .improve, .photographer, "Aim a little lower",
                           detail: "Put their eyes on the upper third of the frame.", arrow: .tiltDown))
        } else if !fullBody && face.rect.w > 0.07 && face.headTop > 0.3 {
            out.append(Cue(.headroom, .improve, .photographer, "Too much space above them",
                           detail: "Aim lower or step closer so their eyes sit near the upper third.", arrow: .tiltDown))
        }

        // Lens choice.
        if a.zoom < 0.75 {
            out.append(Cue(.avoidUltraWide, .improve, .photographer, "Switch off 0.5x for people",
                           detail: "The ultra-wide stretches faces and bodies, worst at the edges.", action: .lens(1)))
        } else if a.zoom < 1.5 && face.rect.w > 0.2 {
            out.append(Cue(.useTele, .improve, .photographer, "Step back and use 2x",
                           detail: "A longer lens flatters faces and softens the background.", arrow: .back, action: .lens(2)))
        }

        // Posing.
        if let body, let span = body.shoulderSpan, face.rect.w > 0.02, faces.count == 1 {
            let yawSmall = (face.yaw.map { abs($0) } ?? 0) < 12
            if span / face.rect.w > 2.45 && yawSmall {
                out.append(Cue(.squareShoulders, .improve, .subject, "Angle their body, face to you",
                               detail: "Shoulders turned about 30° with the face back to the lens looks slimmer and more natural."))
            }
            if armsGlued(body) {
                out.append(Cue(.armsGlued, .improve, .subject, "Hand in a pocket or on the hip",
                               detail: "A little space between arms and waist defines the silhouette."))
            }
        }
        if let r = face.noseRatio {
            if r < 0.40 {
                out.append(Cue(.subjectChinUp, .improve, .subject, "Ask them to lower their chin",
                               detail: "Chin forward and slightly down defines the jawline."))
            } else if r > 0.80 {
                out.append(Cue(.subjectChinDown, .improve, .subject, "Ask them to lift their chin",
                               detail: "Their face is tipping down. Bring the chin forward and up."))
            }
        }

        out += lighting(a, face: face, actor: .photographer)
        out += mergerCues(a, selfie: false)

        if a.scene.clutter > 0.32 && a.zoom < 1.5 {
            out.append(Cue(.clutter, .nice, .photographer, "Busy background: get closer, use 2x",
                           detail: "A tighter frame with a longer lens hides clutter and blurs what is left.", action: .lens(2)))
        }

        // Small subject in a big scene: place them on a third.
        if faces.count == 1 && face.rect.w < 0.09 {
            let cx = face.rect.midX
            if cx > 0.42 && cx < 0.58 {
                let thirdX = cx < 0.5 ? 1.0 / 3 : 2.0 / 3
                target = Rect(x: thirdX - 0.08, y: max(0, face.rect.minY - 0.05), w: 0.16, h: min(0.6, 1 - face.rect.minY))
                out.append(Cue(.thirds, .nice, .photographer, "Try them on a third line",
                               detail: "Off-centre leaves room for the place they are in."))
            }
        }
        return out
    }

    static func armsGlued(_ b: BodyInfo) -> Bool {
        guard let span = b.shoulderSpan, span > 0.01 else { return false }
        func glued(_ s: Joint, _ e: Joint, _ w: Joint, _ h: Joint) -> Bool {
            guard let sh = b[s], let el = b[e], let wr = b[w], let hip = b[h] else { return false }
            let down = el.y > sh.y && wr.y > el.y
            let straight = abs(wr.x - sh.x) < span * 0.2 && abs(el.x - sh.x) < span * 0.2
            let atHip = abs(wr.x - hip.x) < span * 0.45
            return down && straight && atHip
        }
        return glued(.leftShoulder, .leftElbow, .leftWrist, .leftHip) && glued(.rightShoulder, .rightElbow, .rightWrist, .rightHip)
    }

    /// Crops at joints look like amputations: knees, ankles, wrists and elbows at the frame edge.
    static func bodyCrops(_ a: FrameAnalysis, body: BodyInfo?) -> [Cue] {
        guard let b = body else { return [] }
        var out: [Cue] = []
        let knees = [b[.leftKnee], b[.rightKnee]].compactMap { $0 }
        let ankles = [b[.leftAnkle], b[.rightAnkle]].compactMap { $0 }
        if ankles.isEmpty, let lowKnee = knees.max(by: { $0.y < $1.y }), lowKnee.y > 0.84 {
            out.append(Cue(.kneeCrop, .improve, .photographer, "Don't crop at the knees",
                           detail: "Step back to include the feet, or frame higher at mid-thigh.", arrow: .back, marks: knees))
        } else if let lowAnkle = ankles.max(by: { $0.y < $1.y }), lowAnkle.y > 0.95 {
            out.append(Cue(.feetCrop, .improve, .photographer, "Leave room under the feet",
                           detail: "Feet touching the edge look cut off. Step back a little.", arrow: .back, marks: ankles))
        }
        let limbs = [b[.leftWrist], b[.rightWrist], b[.leftElbow], b[.rightElbow]].compactMap { $0 }
        let atEdge = limbs.filter { $0.x < 0.02 || $0.x > 0.98 }
        if !atEdge.isEmpty {
            out.append(Cue(.limbCrop, .nice, .photographer, "An arm is cut at the edge",
                           detail: "Give hands and elbows a little room, or crop well inside the arm.", arrow: .back, marks: atEdge))
        }
        return out
    }

    // MARK: - Group

    static func group(_ a: FrameAnalysis) -> [Cue] {
        var out: [Cue] = []
        if let c = levelCue(a, threshold: 2.5) { out.append(c) }
        let faces = a.subjectFaces.sorted { $0.rect.midX < $1.rect.midX }
        guard !faces.isEmpty else {
            return out + [Cue(.noSubject, .fix, a.side == .front ? .you : .photographer, "Get everyone in the frame")]
        }
        let actor: Who = a.side == .front ? .you : .photographer

        if faces.contains(where: { $0.headTop < 0.005 }) {
            out.append(Cue(.headCut, .fix, actor, "Heads are cut off", detail: "Step back or aim up a little.", arrow: .back))
        }
        if faces.contains(where: { $0.rect.minX < 0.03 || $0.rect.maxX > 0.97 }) {
            out.append(Cue(.edgePerson, .improve, actor, "Someone is at the edge",
                           detail: a.zoom < 0.75 ? "Step back and leave 0.5x: wide lenses stretch people at the edges."
                                                 : "Step back so nobody touches the frame edge.",
                           arrow: .back, action: a.zoom < 0.75 ? .lens(1) : nil))
        }
        let widths = faces.map(\.rect.w)
        if let med = MathX.median(widths) {
            if faces.count >= 3, faces.contains(where: { $0.rect.w < med * 0.55 }) {
                out.append(Cue(.hiddenFace, .improve, .subject, "Bring the back row forward",
                               detail: "Someone is far smaller than the rest and will look lost."))
            }
            var maxGap = 0.0
            for i in 1..<max(1, faces.count) {
                maxGap = max(maxGap, faces[i].rect.minX - faces[i - 1].rect.maxX)
            }
            if faces.count >= 2 && maxGap > med * 2.2 {
                out.append(Cue(.gaps, .improve, .subject, "Ask them to close the gaps",
                               detail: "Shoulders touching reads as a group, gaps read as strangers."))
            }
            if faces.count >= 4 {
                let ys = faces.map(\.eyeY)
                if let lo = ys.min(), let hi = ys.max(), hi - lo < 0.02 {
                    out.append(Cue(.flatHeads, .nice, .subject, "Stagger their head heights",
                                   detail: "Some sitting, leaning or on a step makes a livelier group than a straight row."))
                }
            }
        }
        if a.side == .back && a.attitude.elevation < -18 && !a.attitude.isFlat {
            out.append(Cue(.groupHeight, .nice, .photographer, "Hold the phone at eye level",
                           detail: "Shooting down on a group makes everyone look short.", arrow: .raise))
        }
        if let main = a.facesBySize.first {
            out += lighting(a, face: main, actor: a.side == .front ? .you : .photographer)
        }
        return out
    }

    // MARK: - Scene (no people)

    static func scene(_ a: FrameAnalysis, target: inout Rect?) -> [Cue] {
        var out: [Cue] = []
        if let c = levelCue(a, threshold: 1.5) { out.append(c) }
        let att = a.attitude
        if a.side == .back && !att.isFlat && abs(att.elevation) > 6 && abs(att.elevation) < 28 {
            out.append(Cue(.verticals, .improve, .photographer, "Hold the phone straight up",
                           detail: att.elevation > 0 ? "Tilting up makes buildings lean back. Step back, or use 0.5x and keep it vertical."
                                                     : "Tilting down makes vertical lines lean. Keep the phone upright.",
                           arrow: att.elevation > 0 ? .tiltDown : .tiltUp))
        }
        if a.scene.highlightClip > 0.08 {
            out.append(Cue(.skyBlown, .improve, .photographer, "Tap the bright area to expose",
                           detail: "Part of the frame is pure white. Exposing for it brings back the sky's color."))
        }
        if a.scene.meanLuma < 0.12 {
            out.append(Cue(.lowLight, .nice, .photographer, "Low light: brace and hold still",
                           detail: "Lean on something or hold your breath for the shot."))
        }
        if let sun = a.sun, let rel = sun.relativeAzimuth, abs(rel) < 25, sun.elevation > -1, sun.elevation < 25 {
            out.append(Cue(.intoSun, .nice, .photographer, "Shooting into the sun",
                           detail: "Great for silhouettes. For color and detail, turn so the sun is to your side."))
        }
        if let s = a.scene.salient, s.area < 0.15, abs(s.midX - 0.5) < 0.07 {
            let thirdX = s.midX < 0.5 ? 1.0 / 3 : 2.0 / 3
            target = Rect(x: thirdX - s.w / 2, y: s.minY, w: s.w, h: s.h)
            out.append(Cue(.thirds, .nice, .photographer, "Try the subject on a third line",
                           detail: "Centred works for symmetry. Otherwise a third line adds tension."))
        }
        return out
    }
}
