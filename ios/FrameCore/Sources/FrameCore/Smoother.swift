import Foundation

/// Turns noisy per-frame coaching into calm guidance: a cue must persist before it shows,
/// the main cue stays up long enough to act on, and "ready" must hold before auto-capture.
public final class CueSmoother {
    public struct Shown: Equatable, Sendable {
        public var primary: Cue?
        public var secondary: [Cue]
        public var readiness: Int
        /// Ready continuously for at least `readyHold`.
        public var steadyReady: Bool
        public var mode: ShootMode
        public var levelError: Double?
        public var targetZone: Rect?
        public var eyesClosed: Bool
    }

    public var minPersist: TimeInterval = 0.45
    public var minPersistFix: TimeInterval = 0.25
    public var minDwell: TimeInterval = 1.6
    public var grace: TimeInterval = 0.5
    public var readyHold: TimeInterval = 0.7

    private var firstSeen: [CueID: TimeInterval] = [:]
    private var lastSeen: [CueID: TimeInterval] = [:]
    private var latest: [CueID: Cue] = [:]
    private var primaryID: CueID?
    private var primarySince: TimeInterval = 0
    private var readySince: TimeInterval?
    private var smoothedReadiness: Double = 0

    public init() {}

    public func reset() {
        firstSeen = [:]
        lastSeen = [:]
        latest = [:]
        primaryID = nil
        readySince = nil
        smoothedReadiness = 0
    }

    public func update(_ out: CoachOutput, at t: TimeInterval) -> Shown {
        let present = Set(out.cues.map(\.id))
        for c in out.cues {
            if firstSeen[c.id] == nil || (t - (lastSeen[c.id] ?? t)) > grace { firstSeen[c.id] = t }
            lastSeen[c.id] = t
            latest[c.id] = c
        }
        // Forget cues gone for longer than the grace period.
        for (id, seen) in lastSeen where t - seen > grace {
            lastSeen[id] = nil
            firstSeen[id] = nil
            latest[id] = nil
        }

        func eligible(_ c: Cue) -> Bool {
            guard let f = firstSeen[c.id] else { return false }
            return t - f >= (c.severity == .fix ? minPersistFix : minPersist)
        }

        // Candidates in current priority order (fresh order from this frame, then lingering ones in grace).
        var ordered = out.cues.filter(eligible)
        let lingering = latest.values.filter { !present.contains($0.id) && eligible($0) }
            .sorted { $0.severity < $1.severity }
        ordered += lingering

        var primary: Cue?
        if let pid = primaryID, let current = latest[pid] {
            let best = ordered.first
            let mustSwitch = best.map { $0.severity < current.severity && $0.severity == .fix } ?? false
            let dwelt = t - primarySince >= minDwell
            if mustSwitch || (dwelt && best != nil && best!.id != pid && best!.severity < current.severity) {
                primary = best
            } else {
                primary = current
            }
        } else {
            primary = ordered.first
        }
        if primary?.id != primaryID {
            primaryID = primary?.id
            primarySince = t
        }
        let secondary = Array(ordered.filter { $0.id != primary?.id }.prefix(2))

        smoothedReadiness = smoothedReadiness == 0 ? Double(out.readiness) : smoothedReadiness * 0.6 + Double(out.readiness) * 0.4
        if out.isReady {
            if readySince == nil { readySince = t }
        } else {
            readySince = nil
        }
        let steady = readySince.map { t - $0 >= readyHold } ?? false

        return Shown(primary: primary, secondary: secondary, readiness: Int(smoothedReadiness.rounded()),
                     steadyReady: steady, mode: out.mode, levelError: out.levelError, targetZone: out.targetZone,
                     eyesClosed: out.eyesClosed)
    }
}

/// Decides when to say a cue out loud: only new primaries, never the same one twice in a short spell.
public struct SpeechGate {
    public var minGap: TimeInterval = 2.8
    /// A cue that stays up is repeated at most this often.
    public var repeatAfter: TimeInterval = 12
    private var lastSpoken: TimeInterval = -.infinity
    private var lastByID: [CueID: TimeInterval] = [:]

    public init() {}

    public mutating func shouldSpeak(_ cue: Cue?, at t: TimeInterval) -> Bool {
        guard let cue else { return false }
        guard t - lastSpoken >= minGap else { return false }
        if let prev = lastByID[cue.id], t - prev < repeatAfter { return false }
        lastSpoken = t
        lastByID[cue.id] = t
        return true
    }
}
