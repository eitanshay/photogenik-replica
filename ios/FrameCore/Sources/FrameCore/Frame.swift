import Foundation

public enum CameraSide: String, Codable, Sendable { case front, back }

/// What the user is shooting. `auto` resolves from the camera side and how many people are in frame.
public enum ShootMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto, selfie, portrait, group, scene
    public var id: String { rawValue }
    public var label: String { rawValue }
}

/// How the phone is held, from gravity. Analysis frames are delivered upright for the holder.
public enum HoldOrientation: String, Codable, Sendable {
    case portrait, landscapeLeft, landscapeRight, upsideDown
    public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
}

/// Phone attitude derived from the accelerometer's gravity vector (device coordinates, in g).
public struct Attitude: Equatable, Codable, Sendable {
    /// Rotation of the phone around the lens axis, degrees, 0 = upright portrait, positive = clockwise.
    public var roll: Double
    /// Elevation of the active camera's optical axis, degrees. 0 = aimed at the horizon, + = aimed up.
    public var elevation: Double
    public var hold: HoldOrientation

    public init(roll: Double, elevation: Double, hold: HoldOrientation) {
        self.roll = roll
        self.elevation = elevation
        self.hold = hold
    }

    public static func from(gx: Double, gy: Double, gz: Double, side: CameraSide) -> Attitude {
        let gzc = MathX.clamp(gz, -1, 1)
        let elevation = MathX.deg(asin(side == .back ? gzc : -gzc))
        let roll = MathX.deg(atan2(gx, -gy))
        let hold: HoldOrientation
        if abs(gz) > 0.85 {
            hold = .portrait // flat: orientation is meaningless, treat as portrait
        } else if roll >= -45 && roll <= 45 {
            hold = .portrait
        } else if roll > 45 && roll < 135 {
            hold = .landscapeLeft
        } else if roll < -45 && roll > -135 {
            hold = .landscapeRight
        } else {
            hold = .upsideDown
        }
        return Attitude(roll: roll, elevation: elevation, hold: hold)
    }

    /// Tilt away from level for the current hold, degrees. Positive = rotated clockwise past level.
    public var levelError: Double {
        let nearest = (roll / 90).rounded() * 90
        return MathX.wrap180(roll - nearest)
    }

    /// True when the phone is close to flat (pointing at the floor or the sky), where roll is unreliable.
    public var isFlat: Bool { abs(elevation) > 65 }
}

/// Body joints from the pose detector, in image space.
public enum Joint: String, CaseIterable, Codable, Sendable {
    case nose, leftEye, rightEye, leftEar, rightEar, neck
    case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case root, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
}

public struct BodyInfo: Equatable, Codable, Sendable {
    public var joints: [Joint: Vec2]
    public init(joints: [Joint: Vec2]) { self.joints = joints }
    public subscript(_ j: Joint) -> Vec2? { joints[j] }

    public var shoulderSpan: Double? {
        guard let l = joints[.leftShoulder], let r = joints[.rightShoulder] else { return nil }
        return l.distance(to: r)
    }

    public var bounds: Rect? {
        let pts = Array(joints.values)
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(),
              let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return nil }
        return Rect(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }
}

/// Simple facial geometry measured from landmarks.
public struct FaceInfo: Equatable, Codable, Sendable {
    public var rect: Rect
    /// Degrees. Only the magnitude is used: the sign convention differs between detectors.
    public var yaw: Double?
    /// Degrees, 0 = head upright.
    public var roll: Double?
    /// Capture quality from the detector, 0...1 (sharpness, pose, expression, occlusion).
    public var quality: Double?
    /// Eye openness (height over width of each eye contour). Around 0.25 to 0.35 open, under 0.14 closed.
    public var leftEyeOpen: Double?
    public var rightEyeOpen: Double?
    /// Where the nose tip sits between the eye line (0) and the mouth line (1). About 0.55 to 0.65 when level.
    /// Lower means the chin is up, higher means the chin is down.
    public var noseRatio: Double?
    /// Mean luminance (0...1) of the left and right halves of the face, as seen in the image.
    public var lumaLeft: Double?
    public var lumaRight: Double?

    public init(rect: Rect, yaw: Double? = nil, roll: Double? = nil, quality: Double? = nil,
                leftEyeOpen: Double? = nil, rightEyeOpen: Double? = nil, noseRatio: Double? = nil,
                lumaLeft: Double? = nil, lumaRight: Double? = nil) {
        self.rect = rect
        self.yaw = yaw
        self.roll = roll
        self.quality = quality
        self.leftEyeOpen = leftEyeOpen
        self.rightEyeOpen = rightEyeOpen
        self.noseRatio = noseRatio
        self.lumaLeft = lumaLeft
        self.lumaRight = lumaRight
    }

    /// Approximate eye line, as a y coordinate.
    public var eyeY: Double { rect.minY + rect.h * 0.38 }
    /// Approximate top of the head (the detector's box stops around the hairline).
    public var headTop: Double { rect.minY - rect.h * 0.28 }
    public var faceLuma: Double? {
        guard let l = lumaLeft, let r = lumaRight else { return nil }
        return (l + r) / 2
    }

    public static let closedEye = 0.14

    /// nil when unknown.
    public var eyesClosed: Bool? {
        guard let l = leftEyeOpen, let r = rightEyeOpen else { return nil }
        return min(l, r) < FaceInfo.closedEye
    }
}

/// Whole-frame measurements from the low-resolution luminance image and the person mask.
public struct SceneStats: Equatable, Codable, Sendable {
    public var meanLuma: Double
    /// Mean luminance outside the people, nil when no mask.
    public var backgroundLuma: Double?
    /// Fraction of pixels near white and near black.
    public var highlightClip: Double
    public var shadowClip: Double
    /// Background busyness 0...1 (edge density outside people).
    public var clutter: Double
    /// Background lines colliding with the main head.
    public var mergers: [Merger]
    /// Horizon tilt reported by the horizon detector, degrees, positive = horizon rises to the right.
    public var horizonAngle: Double?
    /// Most attention-grabbing region, if computed.
    public var salient: Rect?
    /// Global sharpness proxy (variance of the Laplacian on the analysis image).
    public var sharpness: Double

    public init(meanLuma: Double = 0.5, backgroundLuma: Double? = nil, highlightClip: Double = 0, shadowClip: Double = 0,
                clutter: Double = 0, mergers: [Merger] = [], horizonAngle: Double? = nil, salient: Rect? = nil,
                sharpness: Double = 0) {
        self.meanLuma = meanLuma
        self.backgroundLuma = backgroundLuma
        self.highlightClip = highlightClip
        self.shadowClip = shadowClip
        self.clutter = clutter
        self.mergers = mergers
        self.horizonAngle = horizonAngle
        self.salient = salient
        self.sharpness = sharpness
    }
}

/// Something in the background that visually collides with a head.
public struct Merger: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// A pole, trunk or edge rising out of the head.
        case vertical
        /// A horizon or wall edge cutting through the head or neck.
        case horizontal
    }
    public var kind: Kind
    public var zone: Rect
    /// Which side has a calmer background, so the fix is to move that way. -1 left, +1 right, 0 unknown.
    public var calmerSide: Int
    public init(kind: Kind, zone: Rect, calmerSide: Int) {
        self.kind = kind
        self.zone = zone
        self.calmerSide = calmerSide
    }
}

/// Where the sun is relative to the camera.
public struct SunContext: Equatable, Codable, Sendable {
    public var elevation: Double
    /// Sun azimuth minus the direction the lens points, -180...180. 0 = shooting straight into the sun.
    public var relativeAzimuth: Double?
    public var phase: LightPhase
    public init(elevation: Double, relativeAzimuth: Double?, phase: LightPhase) {
        self.elevation = elevation
        self.relativeAzimuth = relativeAzimuth
        self.phase = phase
    }
}

/// Everything the coach knows about one analysis frame.
public struct FrameAnalysis: Equatable, Sendable {
    public var side: CameraSide
    public var attitude: Attitude
    /// Displayed zoom (0.5, 1, 2, 3, 5...). 1 = main wide lens.
    public var zoom: Double
    public var hasUltraWide: Bool
    public var faces: [FaceInfo]
    public var bodies: [BodyInfo]
    public var scene: SceneStats
    public var sun: SunContext?
    /// Frame aspect (width / height) in image space.
    public var aspect: Double

    public init(side: CameraSide, attitude: Attitude, zoom: Double = 1, hasUltraWide: Bool = true, faces: [FaceInfo] = [],
                bodies: [BodyInfo] = [], scene: SceneStats = SceneStats(), sun: SunContext? = nil, aspect: Double = 0.75) {
        self.side = side
        self.attitude = attitude
        self.zoom = zoom
        self.hasUltraWide = hasUltraWide
        self.faces = faces
        self.bodies = bodies
        self.scene = scene
        self.sun = sun
        self.aspect = aspect
    }

    /// Faces sorted largest first.
    public var facesBySize: [FaceInfo] { faces.sorted { $0.rect.area > $1.rect.area } }

    /// Faces large enough to count as subjects (ignores tiny passers-by in the background).
    public var subjectFaces: [FaceInfo] {
        guard let biggest = facesBySize.first else { return [] }
        return faces.filter { $0.rect.w >= max(0.035, biggest.rect.w * 0.45) }
    }

    /// The body that belongs to the largest face, else the largest body.
    public var mainBody: BodyInfo? {
        if let face = facesBySize.first {
            let withNose = bodies.filter { b in
                if let n = b[.nose] { return face.rect.insetBy(dx: -face.rect.w * 0.3, dy: -face.rect.h * 0.3).contains(n) }
                return false
            }
            if let b = withNose.first { return b }
        }
        return bodies.max { ($0.bounds?.area ?? 0) < ($1.bounds?.area ?? 0) }
    }
}
