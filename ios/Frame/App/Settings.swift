import Foundation
import Observation

enum VoiceMode: String, CaseIterable, Identifiable {
    case off, selfie, always
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "off"
        case .selfie: return "selfies"
        case .always: return "always"
        }
    }
}

/// User choices, persisted in UserDefaults (the Gemini key lives in the Keychain).
@Observable
@MainActor
final class SettingsStore {
    private let d = UserDefaults.standard

    var mode: ShootMode { didSet { d.set(mode.rawValue, forKey: "mode") } }
    var preferredSide: PreferredSide { didSet { d.set(preferredSide.rawValue, forKey: "preferredSide") } }
    var voice: VoiceMode { didSet { d.set(voice.rawValue, forKey: "voice") } }
    var autoCapture: Bool { didSet { d.set(autoCapture, forKey: "autoCapture") } }
    var handsFree: Bool { didSet { d.set(handsFree, forKey: "handsFree") } }
    var timerSeconds: Int { didSet { d.set(timerSeconds, forKey: "timerSeconds") } }
    var burstCount: Int { didSet { d.set(burstCount, forKey: "burstCount") } }
    var autoSaveBest: Bool { didSet { d.set(autoSaveBest, forKey: "autoSaveBest") } }
    var mirrorSelfies: Bool { didSet { d.set(mirrorSelfies, forKey: "mirrorSelfies") } }
    var showGrid: Bool { didSet { d.set(showGrid, forKey: "showGrid") } }
    var showCoaching: Bool { didSet { d.set(showCoaching, forKey: "showCoaching") } }
    var livePhotos: Bool { didSet { d.set(livePhotos, forKey: "livePhotos") } }
    var rawPhotos: Bool { didSet { d.set(rawPhotos, forKey: "rawPhotos") } }
    var fujiMode: Bool { didSet { d.set(fujiMode, forKey: "fujiMode") } }
    var fujiIntent: FujiIntent { didSet { d.set(fujiIntent.rawValue, forKey: "fujiIntent") } }
    var fujiLook: FujiLook { didSet { d.set(fujiLook.rawValue, forKey: "fujiLook") } }
    var fujiCrop: FujiCrop { didSet { d.set(fujiCrop.rawValue, forKey: "fujiCrop") } }
    var directorModel: String { didSet { d.set(directorModel, forKey: "directorModel") } }
    var geminiKey: String { didSet { KeychainStore.write(geminiKey) } }

    init() {
        mode = ShootMode(rawValue: d.string(forKey: "mode") ?? "") ?? .auto
        preferredSide = PreferredSide(rawValue: d.string(forKey: "preferredSide") ?? "") ?? .either
        voice = VoiceMode(rawValue: d.string(forKey: "voice") ?? "") ?? .selfie
        autoCapture = d.object(forKey: "autoCapture") as? Bool ?? false
        handsFree = d.object(forKey: "handsFree") as? Bool ?? false
        timerSeconds = d.object(forKey: "timerSeconds") as? Int ?? 0
        burstCount = d.object(forKey: "burstCount") as? Int ?? 5
        autoSaveBest = d.object(forKey: "autoSaveBest") as? Bool ?? true
        mirrorSelfies = d.object(forKey: "mirrorSelfies") as? Bool ?? true
        showGrid = d.object(forKey: "showGrid") as? Bool ?? true
        showCoaching = d.object(forKey: "showCoaching") as? Bool ?? true
        livePhotos = d.object(forKey: "livePhotos") as? Bool ?? false
        rawPhotos = d.object(forKey: "rawPhotos") as? Bool ?? false
        fujiMode = d.object(forKey: "fujiMode") as? Bool ?? false
        fujiIntent = FujiIntent(rawValue: d.string(forKey: "fujiIntent") ?? "") ?? .auto
        fujiLook = FujiLook(rawValue: d.string(forKey: "fujiLook") ?? "") ?? .auto
        fujiCrop = FujiCrop(rawValue: d.integer(forKey: "fujiCrop")) ?? .mm35
        let model = d.string(forKey: "directorModel") ?? DirectorModels.default
        directorModel = DirectorModels.all.contains(model) ? model : DirectorModels.default
        geminiKey = KeychainStore.read()
    }

    var coach: CoachSettings { CoachSettings(mode: mode, preferredSide: preferredSide) }
}
