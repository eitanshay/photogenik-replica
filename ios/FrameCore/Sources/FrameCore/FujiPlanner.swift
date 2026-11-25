import Foundation

// Plans settings for a Fujifilm X100VI from what the iPhone sees: the light level it meters,
// who is in frame, and what the photographer is going for.
//
// Camera facts used (from Fujifilm's X100VI specifications):
// 23mm f/2 (35mm equivalent), f/2 to f/16 in 1/3 steps, built-in 4-stop ND, leaf shutter to 1/4000,
// electronic shutter to 1/180000, ISO 125 to 12800 (64 and 25600+ extended), 6-stop IBIS,
// digital teleconverter at 50mm and 70mm equivalent, APS-C sensor.

public enum FujiIntent: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto, portrait, street, landscape, group, action, night
    public var id: String { rawValue }
    public var label: String { rawValue }
}

public enum FujiLook: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto, natural, documentary, moody, soft, vivid, golden, night, mono
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .mono: return "b&w"
        default: return rawValue
        }
    }
}

/// Field of view to plan for: the lens, or one of the digital teleconverter crops.
public enum FujiCrop: Int, CaseIterable, Codable, Identifiable, Sendable {
    case mm35 = 35, mm50 = 50, mm70 = 70
    public var id: Int { rawValue }
    public var label: String { "\(rawValue)mm" }
    public var focalEquivalent: Double { Double(rawValue) }
}

public enum FujiShutterKind: String, Codable, Sendable {
    case mechanical, electronic
    public var label: String { self == .mechanical ? "MS (leaf)" : "ES (electronic)" }
}

/// One in-camera film recipe: every setting in the X100VI's image quality menu that shapes the JPEG.
public struct FilmRecipe: Equatable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var look: FujiLook
    public var simulation: String
    /// 100, 200 or 400. DR200 needs ISO 250 or higher, DR400 needs ISO 500 or higher.
    public var dynamicRange: Int
    public var grain: String
    public var colorChrome: String
    public var colorChromeBlue: String
    public var whiteBalance: String
    public var wbShiftR: Int
    public var wbShiftB: Int
    public var highlight: Double
    public var shadow: Double
    public var color: Int
    public var sharpness: Int
    public var noiseReduction: Int
    public var clarity: Int
    public var why: String

    /// Rows for the recipe table, in the order they appear in the camera's menu.
    public func rows(effectiveDR: Int) -> [(String, String)] {
        func s(_ v: Int) -> String { v > 0 ? "+\(v)" : "\(v)" }
        func h(_ v: Double) -> String {
            let t = v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
            return v > 0 ? "+" + t : t
        }
        return [
            ("Film simulation", simulation),
            ("Grain", grain),
            ("Color chrome", colorChrome),
            ("Color chrome FX blue", colorChromeBlue),
            ("White balance", "\(whiteBalance), R\(s(wbShiftR)) B\(s(wbShiftB))"),
            ("Dynamic range", effectiveDR == dynamicRange ? "DR\(dynamicRange)" : "DR\(effectiveDR) (DR\(dynamicRange) needs ISO \(dynamicRange == 400 ? 500 : 250)+)"),
            ("Highlight", h(highlight)),
            ("Shadow", h(shadow)),
            ("Color", s(color)),
            ("Sharpness", s(sharpness)),
            ("High ISO NR", s(noiseReduction)),
            ("Clarity", s(clarity))
        ]
    }
}

public enum FilmRecipes {
    public static let all: [FilmRecipe] = [natural, documentary, moody, soft, vivid, golden, night, mono]

    public static let natural = FilmRecipe(
        name: "True to life", look: .natural, simulation: "Reala Ace", dynamicRange: 400, grain: "Off",
        colorChrome: "Weak", colorChromeBlue: "Off", whiteBalance: "Auto", wbShiftR: 0, wbShiftB: 0,
        highlight: -1, shadow: 0, color: 0, sharpness: 0, noiseReduction: -2, clarity: 0,
        why: "Reala Ace is Fujifilm's most neutral, accurate color. A safe default for people and places.")

    public static let documentary = FilmRecipe(
        name: "Street documentary", look: .documentary, simulation: "Classic Chrome", dynamicRange: 400,
        grain: "Weak, small", colorChrome: "Strong", colorChromeBlue: "Weak", whiteBalance: "Auto", wbShiftR: 2, wbShiftB: -3,
        highlight: 0, shadow: 1, color: 2, sharpness: 0, noiseReduction: -4, clarity: 0,
        why: "Classic Chrome's muted color and firm shadows, warmed slightly so skin does not go gray.")

    public static let moody = FilmRecipe(
        name: "Moody negative", look: .moody, simulation: "Classic Negative", dynamicRange: 400,
        grain: "Weak, large", colorChrome: "Strong", colorChromeBlue: "Off", whiteBalance: "Auto", wbShiftR: 1, wbShiftB: -2,
        highlight: -1, shadow: 1, color: 2, sharpness: -1, noiseReduction: -4, clarity: -1,
        why: "Classic Negative's cyan shadows and hard contrast, like drugstore film. Best for travel and street.")

    public static let soft = FilmRecipe(
        name: "Soft portrait", look: .soft, simulation: "Astia/Soft", dynamicRange: 200,
        grain: "Off", colorChrome: "Weak", colorChromeBlue: "Off", whiteBalance: "Auto", wbShiftR: 1, wbShiftB: -1,
        highlight: -1, shadow: -1, color: 0, sharpness: -1, noiseReduction: -4, clarity: -2,
        why: "Astia renders skin gently; negative clarity acts like a diffusion filter.")

    public static let vivid = FilmRecipe(
        name: "Vivid landscape", look: .vivid, simulation: "Velvia/Vivid", dynamicRange: 200,
        grain: "Off", colorChrome: "Strong", colorChromeBlue: "Strong", whiteBalance: "Daylight", wbShiftR: 0, wbShiftB: -1,
        highlight: -1, shadow: 0, color: 0, sharpness: 1, noiseReduction: -2, clarity: 2,
        why: "Velvia is already saturated, so color stays at 0; color chrome deepens skies and foliage. Avoid it for faces.")

    public static let golden = FilmRecipe(
        name: "Golden hour", look: .golden, simulation: "Reala Ace", dynamicRange: 400,
        grain: "Weak, small", colorChrome: "Strong", colorChromeBlue: "Weak", whiteBalance: "Daylight", wbShiftR: 2, wbShiftB: -3,
        highlight: -1, shadow: 0, color: 1, sharpness: 0, noiseReduction: -4, clarity: 0,
        why: "Daylight white balance keeps the warm light instead of letting Auto neutralise it.")

    public static let night = FilmRecipe(
        name: "Night city", look: .night, simulation: "Nostalgic Neg.", dynamicRange: 200,
        grain: "Strong, small", colorChrome: "Off", colorChromeBlue: "Off", whiteBalance: "Auto", wbShiftR: 0, wbShiftB: -2,
        highlight: -1, shadow: 1, color: 0, sharpness: -1, noiseReduction: -4, clarity: 0,
        why: "Warm, low-contrast highlights for street lights; grain turns high-ISO noise into texture.")

    public static let mono = FilmRecipe(
        name: "Black and white", look: .mono, simulation: "Acros + Ye filter", dynamicRange: 200,
        grain: "Strong, small", colorChrome: "Off", colorChromeBlue: "Off", whiteBalance: "Auto", wbShiftR: 0, wbShiftB: 0,
        highlight: 0, shadow: 2, color: 0, sharpness: 1, noiseReduction: -4, clarity: 2,
        why: "Acros with the yellow filter darkens skies a little and keeps skin bright. Use the red filter for drama.")

    public static func recipe(for look: FujiLook) -> FilmRecipe {
        all.first { $0.look == look } ?? natural
    }
}

/// What the planner knows about the moment.
public struct FujiInput: Equatable, Sendable {
    /// Scene brightness at ISO 100 (EV100) from the iPhone's meter.
    public var ev100: Double
    public var intent: FujiIntent
    public var look: FujiLook
    public var crop: FujiCrop
    public var people: Int
    /// Width of the main face as a fraction of the frame width, if a face is in view.
    public var faceWidth: Double?
    /// The phone is held in landscape (frame width is the long side).
    public var landscapeHold: Bool
    /// How much brighter the background is than the main face, in stops (positive = backlit).
    public var backlightStops: Double?
    /// Share of the frame that is blown to white.
    public var highlightClip: Double
    public var sun: LightPhase?

    public init(ev100: Double, intent: FujiIntent = .auto, look: FujiLook = .auto, crop: FujiCrop = .mm35, people: Int = 0,
                faceWidth: Double? = nil, landscapeHold: Bool = false, backlightStops: Double? = nil,
                highlightClip: Double = 0, sun: LightPhase? = nil) {
        self.ev100 = ev100
        self.intent = intent
        self.look = look
        self.crop = crop
        self.people = people
        self.faceWidth = faceWidth
        self.landscapeHold = landscapeHold
        self.backlightStops = backlightStops
        self.highlightClip = highlightClip
        self.sun = sun
    }
}

public struct FujiPlan: Equatable, Sendable {
    public var intent: FujiIntent
    public var aperture: Double
    /// Seconds.
    public var shutter: Double
    public var shutterKind: FujiShutterKind
    public var iso: Int
    public var nd: Bool
    /// Exposure compensation in stops (thirds).
    public var compensation: Double
    public var metering: String
    public var focus: String
    public var flash: String?
    public var crop: FujiCrop
    /// Estimated distance to the main subject, meters.
    public var subjectDistance: Double?
    /// Near and far limits of sharp focus at that distance, meters (far = .infinity past hyperfocal).
    public var depthOfField: (near: Double, far: Double)?
    public var recipe: FilmRecipe
    public var dynamicRange: Int
    /// Why each choice, in plain words.
    public var reasons: [String]
    /// Things that will go wrong unless the photographer acts (too dark, motion blur...).
    public var warnings: [String]
    public var ev100: Double

    public static func == (a: FujiPlan, b: FujiPlan) -> Bool {
        a.intent == b.intent && a.aperture == b.aperture && a.shutter == b.shutter && a.shutterKind == b.shutterKind
            && a.iso == b.iso && a.nd == b.nd && a.compensation == b.compensation && a.metering == b.metering
            && a.focus == b.focus && a.flash == b.flash && a.crop == b.crop && a.recipe == b.recipe
            && a.dynamicRange == b.dynamicRange && a.reasons == b.reasons && a.warnings == b.warnings
            && a.subjectDistance == b.subjectDistance && a.ev100 == b.ev100
            && a.depthOfField?.near == b.depthOfField?.near && a.depthOfField?.far == b.depthOfField?.far
    }
}

public enum FujiScale {
    public static let apertures: [Double] = [2, 2.2, 2.5, 2.8, 3.2, 3.6, 4, 4.5, 5, 5.6, 6.4, 7.1, 8, 9, 10, 11, 13, 14, 16]
    public static let isos: [Int] = [125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200,
                                     4000, 5000, 6400, 8000, 10000, 12800]
    /// Shutter speeds in 1/3 stops, as seconds, from 30 s to 1/180000.
    public static let shutters: [Double] = {
        let long: [Double] = [30, 25, 20, 15, 13, 10, 8, 6, 5, 4, 3, 2.5, 2, 1.6, 1.3, 1]
        let denominators: [Double] = [1.3, 1.6, 2, 2.5, 3, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30, 40, 50, 60, 80, 100, 125, 160,
                                      200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000,
                                      6400, 8000, 10000, 12800, 16000, 20000, 25000, 32000, 40000, 50000, 64000, 80000,
                                      100000, 128000, 160000, 180000]
        return long + denominators.map { 1 / $0 }
    }()

    static func nearest(_ v: Double, in list: [Double]) -> Double {
        list.min { abs(log2($0 / v)) < abs(log2($1 / v)) } ?? v
    }

    public static func aperture(_ v: Double) -> Double { nearest(MathX.clamp(v, 2, 16), in: apertures) }
    public static func shutter(_ v: Double) -> Double { nearest(MathX.clamp(v, 1.0 / 180000, 30), in: shutters) }
    public static func iso(_ v: Double) -> Int {
        let c = MathX.clamp(v, 125, 12800)
        return isos.min { abs(log2(Double($0) / c)) < abs(log2(Double($1) / c)) } ?? 125
    }
    /// Rounds to 1/3 stop.
    public static func thirds(_ v: Double) -> Double { (v * 3).rounded() / 3 }
}

public enum FujiFormat {
    public static func aperture(_ a: Double) -> String {
        a == a.rounded() ? "f/\(Int(a))" : String(format: "f/%.1f", a)
    }

    public static func shutter(_ t: Double) -> String {
        if t >= 1 { return t == t.rounded() ? "\(Int(t))s" : String(format: "%.1fs", t) }
        let d = 1 / t
        return d < 10 ? String(format: "1/%.1f", d).replacingOccurrences(of: ".0", with: "") : "1/\(Int(d.rounded()))"
    }

    public static func compensation(_ c: Double) -> String {
        let thirds = Int((c * 3).rounded())
        if thirds == 0 { return "±0" }
        let sign = thirds > 0 ? "+" : "−"
        let whole = abs(thirds) / 3, rest = abs(thirds) % 3
        if rest == 0 { return "\(sign)\(whole)" }
        return whole == 0 ? "\(sign)\(rest)/3" : "\(sign)\(whole) \(rest)/3"
    }

    public static func meters(_ m: Double) -> String {
        if m.isInfinite { return "∞" }
        return m < 10 ? String(format: "%.1f m", m) : "\(Int(m.rounded())) m"
    }
}

public enum FujiOptics {
    public static let focalLength = 23.0          // mm, real
    public static let circleOfConfusion = 0.02    // mm, APS-C
    public static let realFaceWidth = 0.16        // m, adult face incl. ears region the detector boxes

    /// Distance to a face from its width in the frame.
    /// `frameWidthEquivalent` is the frame's width in 35mm-equivalent millimetres (36 landscape, 24 portrait).
    public static func distance(faceWidth: Double, focalEquivalent: Double, frameWidthEquivalent: Double) -> Double? {
        guard faceWidth > 0.005 else { return nil }
        return realFaceWidth * focalEquivalent / (faceWidth * frameWidthEquivalent)
    }

    /// Hyperfocal distance in metres. A teleconverter crop enlarges the image, so blur must be smaller.
    public static func hyperfocal(aperture: Double, crop: FujiCrop = .mm35) -> Double {
        let c = circleOfConfusion * 35 / crop.focalEquivalent
        let f = focalLength
        return (f * f / (aperture * c) + f) / 1000
    }

    public static func depthOfField(distance d: Double, aperture: Double, crop: FujiCrop = .mm35) -> (near: Double, far: Double) {
        let H = hyperfocal(aperture: aperture, crop: crop)
        let f = focalLength / 1000
        let near = d * (H - f) / (H + d - 2 * f)
        let far = d < H ? d * (H - f) / (H - d) : .infinity
        return (near, far)
    }
}

public enum FujiPlanner {
    /// Fastest speed the leaf shutter is trusted to deliver at an aperture. Leaf shutters slow down wide open;
    /// these limits are deliberately conservative, so the plan reaches for the ND filter or ES first.
    public static func leafLimit(aperture a: Double) -> Double {
        if a < 4 { return 1.0 / 1000 }
        if a < 8 { return 1.0 / 2000 }
        return 1.0 / 4000
    }

    public static func resolveIntent(_ input: FujiInput) -> FujiIntent {
        if input.intent != .auto { return input.intent }
        if input.people >= 3 { return .group }
        if input.people >= 1 { return .portrait }
        return input.ev100 < 6 ? .night : .landscape
    }

    public static func resolveLook(_ look: FujiLook, intent: FujiIntent, sun: LightPhase?) -> FujiLook {
        if look != .auto { return look }
        let golden = sun == .goldenHour
        switch intent {
        case .portrait: return golden ? .golden : .soft
        case .street: return .documentary
        case .landscape: return golden ? .golden : .vivid
        case .group, .action, .auto: return golden ? .golden : .natural
        case .night: return .night
        }
    }

    struct Targets {
        var aperture: Double
        /// Longest acceptable exposure for the subject's motion.
        var slowest: Double
        var widest: Double
        var narrowest: Double
        var isoCap: Double
    }

    static func targets(_ intent: FujiIntent, people: Int) -> Targets {
        switch intent {
        case .portrait:
            return Targets(aperture: people >= 2 ? 2.8 : 2, slowest: 1.0 / 250, widest: 2, narrowest: 5.6, isoCap: 3200)
        case .street:
            return Targets(aperture: 8, slowest: 1.0 / 500, widest: 4, narrowest: 11, isoCap: 6400)
        case .landscape:
            return Targets(aperture: 8, slowest: 1.0 / 60, widest: 4, narrowest: 11, isoCap: 800)
        case .group:
            return Targets(aperture: people >= 6 ? 8 : 5.6, slowest: 1.0 / 250, widest: 2.8, narrowest: 8, isoCap: 3200)
        case .action:
            return Targets(aperture: 4, slowest: 1.0 / 1000, widest: 2.8, narrowest: 8, isoCap: 6400)
        case .night, .auto:
            return Targets(aperture: 2, slowest: 1.0 / 30, widest: 2, narrowest: 4, isoCap: 6400)
        }
    }

    static func exposureTime(ev: Double, aperture: Double, iso: Double, ndStops: Double, comp: Double) -> Double {
        aperture * aperture / pow(2, ev + log2(iso / 100) - ndStops - comp)
    }

    public static func plan(_ input: FujiInput) -> FujiPlan {
        let intent = resolveIntent(input)
        let look = resolveLook(input.look, intent: intent, sun: input.sun)
        let recipe = FilmRecipes.recipe(for: look)
        let peopleIntent = intent == .portrait || intent == .group
        var reasons: [String] = []
        var warnings: [String] = []
        let ev = input.ev100

        // Exposure compensation and metering from the light's shape.
        var comp = 0.0
        var metering = "Multi"
        var flash: String?
        let backlit = (input.backlightStops ?? 0) > 1 && input.people > 0
        if backlit && peopleIntent {
            comp = min(1.7, FujiScale.thirds((input.backlightStops ?? 1) * 0.7))
            metering = "Multi (or Spot on the face, ±0)"
            reasons.append("Backlit: +\(FujiFormat.compensation(comp).dropFirst()) so the face is not a silhouette.")
            if ev > 10 { flash = "Fill flash at −1 2/3: the leaf shutter syncs at every speed, so it works in full sun." }
        } else if input.highlightClip > 0.08 && input.people == 0 {
            comp = -2.0 / 3
            reasons.append("Bright highlights: −2/3 keeps the sky's color.")
        } else if intent == .night {
            comp = -1.0 / 3
            reasons.append("Night: −1/3 keeps the dark dark and the lights from blowing.")
        } else if intent == .landscape && input.sun == .goldenHour {
            comp = -1.0 / 3
            reasons.append("Golden light: −1/3 deepens the color in the sky.")
        }
        if intent == .night && input.people > 0 && flash == nil {
            flash = "Flash at −1 with a slow shutter (1/15 to 1/30) lights the face and keeps the city glow."
        }

        // Solve aperture, shutter, ISO.
        let t0 = targets(intent, people: input.people)
        var aperture = t0.aperture
        var iso = 125.0
        var nd = false
        var kind = FujiShutterKind.mechanical
        func time() -> Double { exposureTime(ev: ev, aperture: aperture, iso: iso, ndStops: nd ? 4 : 0, comp: comp) }
        var t = time()

        if t > t0.slowest {
            // Too dark for the motion we want to freeze: ISO first, then open up, then accept a slower shutter.
            let needISO = iso * t / t0.slowest
            iso = min(t0.isoCap, needISO)
            t = time()
            if t > t0.slowest && aperture > t0.widest {
                let open = aperture / (t / t0.slowest).squareRoot()
                aperture = max(t0.widest, open)
                t = time()
            }
            // People holding still for a photo tolerate one stop slower before ISO goes past its comfort cap.
            let relaxed = (peopleIntent || intent == .street) ? t0.slowest * 2 : t0.slowest
            if t > t0.slowest && t <= relaxed {
                reasons.append("\(FujiFormat.shutter(FujiScale.shutter(t))) is fine if they hold still for the shot.")
            }
            if t > relaxed {
                iso = min(12800, iso * t / relaxed)
                t = time()
                if t <= relaxed * 1.05 && relaxed > t0.slowest {
                    reasons.append("\(FujiFormat.shutter(FujiScale.shutter(t))) is fine if they hold still for the shot.")
                }
                if iso > 6400 { warnings.append("ISO \(FujiScale.iso(iso)) is noisy. Grain in the recipe helps it look intentional.") }
            }
            if t > relaxed * 1.05 {
                let handheld = intent == .landscape ? 1.0 / 4 : 1.0 / 15
                if t > handheld {
                    warnings.append("Too dark to hand-hold at \(FujiFormat.shutter(FujiScale.shutter(t))): brace on something, use a tripod, or flash.")
                } else if peopleIntent || intent == .street || intent == .action {
                    warnings.append("At \(FujiFormat.shutter(FujiScale.shutter(t))) moving people will blur. IBIS holds the camera, not them.")
                } else {
                    reasons.append("IBIS makes \(FujiFormat.shutter(FujiScale.shutter(t))) hand-holdable for still scenes.")
                }
            }
        } else {
            // Bright: keep the aperture if it matters, else stop down; then ND; then the electronic shutter.
            let wantsShallow = intent == .portrait || intent == .night
            if !wantsShallow && t < leafLimit(aperture: aperture) && aperture < t0.narrowest {
                while aperture < t0.narrowest && time() < leafLimit(aperture: aperture) {
                    aperture = FujiScale.apertures.first { $0 > aperture } ?? 16
                }
                t = time()
            }
            if t < leafLimit(aperture: aperture) {
                if intent == .action {
                    kind = .electronic
                    reasons.append("Electronic shutter for speeds past the leaf shutter; the ND would slow you down.")
                } else {
                    let withND = exposureTime(ev: ev, aperture: aperture, iso: iso, ndStops: 4, comp: comp)
                    if withND > t0.slowest * 2 {
                        kind = .electronic
                        reasons.append("ES instead of the ND: with the ND the shutter would be too slow for this subject.")
                    } else {
                        nd = true
                        t = withND
                        if t < leafLimit(aperture: aperture) {
                            kind = .electronic
                            reasons.append("ND on, and still too bright for the leaf shutter at \(FujiFormat.aperture(aperture)): switch to ES.")
                        } else {
                            reasons.append("ND on: at \(FujiFormat.aperture(aperture)) in this light the leaf shutter cannot go fast enough.")
                        }
                    }
                }
            }
        }

        // Dynamic range: recipes ask for DR200 or DR400, which need ISO 250 or 500. Raise ISO for contrasty scenes
        // when the shutter has room, otherwise fall back.
        var dr = recipe.dynamicRange
        let contrasty = backlit || input.highlightClip > 0.04 || input.sun == .harsh
        if dr == 400 && iso < 500 && contrasty {
            let tNew = t * iso / 500
            if tNew >= (kind == .mechanical ? leafLimit(aperture: aperture) : 1.0 / 180000) {
                iso = 500
                t = tNew
                reasons.append("ISO 500 unlocks DR400, which holds the highlights in this contrast.")
            }
        }
        let isoFinal = FujiScale.iso(iso)
        if isoFinal < 250 { dr = 100 } else if isoFinal < 500 { dr = min(dr, 200) }

        // Round to settings the camera has.
        let apertureFinal = FujiScale.aperture(aperture)
        let shutterFinal = FujiScale.shutter(t)
        if kind == .mechanical && shutterFinal < 1.0 / 4000 { kind = .electronic }

        // Reasons for the main choices.
        switch intent {
        case .portrait:
            reasons.insert("\(FujiFormat.aperture(apertureFinal)) separates the subject from the background.", at: 0)
        case .street:
            let h = FujiOptics.hyperfocal(aperture: apertureFinal, crop: input.crop)
            reasons.insert("\(FujiFormat.aperture(apertureFinal)) with zone focus: sharp from \(FujiFormat.meters(h / 2)) to infinity, no waiting for AF.", at: 0)
        case .landscape:
            reasons.insert("\(FujiFormat.aperture(apertureFinal)) is the lens's sharpest corner to corner, with deep focus.", at: 0)
        case .group:
            reasons.insert("\(FujiFormat.aperture(apertureFinal)) keeps every row of faces sharp.", at: 0)
        case .action:
            reasons.insert("\(FujiFormat.shutter(shutterFinal)) freezes movement.", at: 0)
        case .night, .auto:
            reasons.insert("Wide open at \(FujiFormat.aperture(apertureFinal)) to gather light.", at: 0)
        }

        // Focus and depth of field.
        var distance: Double?
        if let fw = input.faceWidth {
            distance = FujiOptics.distance(faceWidth: fw, focalEquivalent: input.crop.focalEquivalent,
                                           frameWidthEquivalent: input.landscapeHold ? 36 : 24)
        }
        let focus: String
        var dof: (near: Double, far: Double)?
        switch intent {
        case .portrait:
            focus = "AF-S · single point · face and eye detection on"
        case .group:
            focus = "AF-S · face detection on · focus on the middle row"
        case .street:
            let h = FujiOptics.hyperfocal(aperture: apertureFinal, crop: input.crop)
            focus = "MF zone focus at \(FujiFormat.meters(h)) (sharp from \(FujiFormat.meters(h / 2)) to ∞)"
            distance = distance ?? h
        case .landscape:
            let h = FujiOptics.hyperfocal(aperture: apertureFinal, crop: input.crop)
            focus = "AF-S on something a third into the scene, or MF at \(FujiFormat.meters(h))"
            distance = distance ?? h
        case .action:
            focus = "AF-C · tracking · subject detection on"
        case .night, .auto:
            focus = "AF-S · single point on a lit edge"
        }
        if let d = distance {
            dof = FujiOptics.depthOfField(distance: d, aperture: apertureFinal, crop: input.crop)
        }

        // Framing advice for close portraits at 35mm.
        if intent == .portrait, input.crop == .mm35, let d = distance, d < 1.0, input.people == 1 {
            warnings.append("At \(FujiFormat.meters(d)) a 35mm lens enlarges noses. Step back to about 1.5 m and use the 50mm teleconverter.")
        }
        if kind == .electronic {
            if flash != nil { flash = nil; warnings.append("Flash does not work with the electronic shutter.") }
            if intent == .action || intent == .street {
                warnings.append("ES can bend fast-moving subjects (rolling shutter). Fine for most street scenes.")
            }
        }

        return FujiPlan(intent: intent, aperture: apertureFinal, shutter: shutterFinal, shutterKind: kind, iso: isoFinal,
                        nd: nd, compensation: FujiScale.thirds(comp), metering: metering, focus: focus, flash: flash,
                        crop: input.crop, subjectDistance: distance, depthOfField: dof, recipe: recipe, dynamicRange: dr,
                        reasons: reasons, warnings: warnings, ev100: ev)
    }

    /// Scene brightness at ISO 100 from a camera's current exposure.
    /// `targetOffset` is how far the current exposure sits from the meter's target, in stops (+ = brighter than target).
    public static func ev100(aperture: Double, exposureSeconds: Double, iso: Double, targetOffset: Double = 0) -> Double {
        guard aperture > 0, exposureSeconds > 0, iso > 0 else { return 0 }
        return log2(aperture * aperture / exposureSeconds) - log2(iso / 100) + targetOffset
    }

    /// Zoom factor (relative to the device's widest view) that matches a 35mm-equivalent focal length,
    /// given the device's horizontal field of view at zoom 1.
    public static func zoomFactor(forEquivalent focal: Double, deviceHorizontalFOV fovDegrees: Double) -> Double {
        guard fovDegrees > 1 else { return 1 }
        // Match the long side: a 35mm frame is 36 mm wide.
        return tan(MathX.rad(fovDegrees) / 2) * focal / 18
    }

    /// One line for the director prompt.
    public static func summary(_ p: FujiPlan) -> String {
        var s = "\(FujiFormat.aperture(p.aperture)), \(FujiFormat.shutter(p.shutter)), ISO \(p.iso)"
        if p.nd { s += ", ND on" }
        if p.compensation != 0 { s += ", \(FujiFormat.compensation(p.compensation)) EV" }
        s += ", \(p.shutterKind == .mechanical ? "leaf shutter" : "electronic shutter"), \(p.crop.label), \(p.recipe.simulation) (\(p.recipe.name))"
        return s
    }
}
