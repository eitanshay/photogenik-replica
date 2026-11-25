import AVFoundation
import Observation

/// On-device text to speech. Free, offline, and keeps playing with the screen locked (audio background mode).
@Observable
final class Narrator: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Narrator()

    private let synth = AVSpeechSynthesizer()
    private(set) var speakingPlaceID: String?
    private(set) var isPaused = false
    private(set) var progress: Double = 0
    private var totalLength = 1
    private var current: AVSpeechUtterance?

    override init() {
        super.init()
        synth.delegate = self
    }

    var isSpeaking: Bool { speakingPlaceID != nil }

    /// The best installed English voice: Premium, then Enhanced, then default; never the novelty voices.
    static func bestVoice(language: String = "en-US") -> AVSpeechSynthesisVoice? {
        let prefix = String(language.prefix(2))
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) && !$0.voiceTraits.contains(.isNoveltyVoice) }
        let exact = voices.filter { $0.language == language }
        let pool = exact.isEmpty ? voices : exact
        return pool.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: language)
    }

    private static func rank(_ v: AVSpeechSynthesisVoice) -> Int {
        switch v.quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }

    static var hasHighQualityVoice: Bool {
        guard let v = bestVoice() else { return false }
        return v.quality == .premium || v.quality == .enhanced
    }

    func speak(_ text: String, placeID: String, rate: Double) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.bestVoice()
        u.rate = Float(rate)
        u.prefersAssistiveTechnologySettings = false
        u.postUtteranceDelay = 0.2
        totalLength = max(1, (text as NSString).length)
        progress = 0
        speakingPlaceID = placeID
        isPaused = false
        current = u
        synth.speak(u)
    }

    func togglePause() {
        if synth.isPaused {
            synth.continueSpeaking()
            isPaused = false
        } else if synth.isSpeaking {
            synth.pauseSpeaking(at: .word)
            isPaused = true
        }
    }

    func stop() {
        current = nil
        if synth.isSpeaking || synth.isPaused { synth.stopSpeaking(at: .immediate) }
        speakingPlaceID = nil
        isPaused = false
        progress = 0
    }

    private func finish() {
        current = nil
        speakingPlaceID = nil
        isPaused = false
        progress = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let p = Double(characterRange.location + characterRange.length) / Double(totalLength)
        DispatchQueue.main.async { if utterance === self.current { self.progress = p } }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { if utterance === self.current { self.finish() } }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { if utterance === self.current { self.finish() } }
    }
}
