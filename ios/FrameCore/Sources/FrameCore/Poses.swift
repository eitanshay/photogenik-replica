import Foundation

/// A short posing or framing playbook per kind of shot, shown in the Pose ideas sheet.
public struct PoseTip: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public var title: String
    public var how: String
}

public struct PoseSet: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var tips: [PoseTip]
}

public enum PoseLibrary {
    public static func sets(for mode: ShootMode) -> [PoseSet] {
        switch mode {
        case .selfie, .auto: return [selfie, travel]
        case .portrait: return [standing, sitting, couple, travel]
        case .group: return [group, couple]
        case .scene: return [travel, scene]
        }
    }

    public static let selfie = PoseSet(name: "Selfie", tips: [
        PoseTip(title: "Phone above eye level", how: "Arm out, phone a little higher than your eyes, tilted down toward you."),
        PoseTip(title: "Chin forward and down", how: "Push your face slightly toward the lens, then tip the chin down. It defines the jaw."),
        PoseTip(title: "Three-quarter turn", how: "Turn your face 10 to 20 degrees to your better side, eyes back to the lens."),
        PoseTip(title: "Look at the lens", how: "Look at the camera dot, not your face on screen, for eye contact."),
        PoseTip(title: "Soft squint", how: "Lift the lower eyelids a touch, like a slight smile with the eyes. It reads confident."),
        PoseTip(title: "Shoulders down", how: "Drop and relax your shoulders, then lengthen the neck."),
        PoseTip(title: "Light in your face", how: "Face the window or the brightest part of the sky. Never have it behind you.")
    ])

    public static let standing = PoseSet(name: "Standing", tips: [
        PoseTip(title: "Angle the body", how: "Turn the body 30 to 45 degrees from the camera, then bring the face back to the lens."),
        PoseTip(title: "Weight on the back leg", how: "Shift weight to the back foot and bend the front knee slightly."),
        PoseTip(title: "Give hands a job", how: "Hand in a pocket, thumb in a belt loop, touching the collar, or holding a bag strap."),
        PoseTip(title: "Space at the waist", how: "Keep a small gap between arms and torso so the waist reads."),
        PoseTip(title: "Walk toward me", how: "Walk slowly toward the camera looking down or away, and burst. Natural every time."),
        PoseTip(title: "Lean on something", how: "One shoulder on a wall, ankles crossed. Instantly relaxed."),
        PoseTip(title: "Camera at waist height", how: "For full-body shots, hold the phone at waist height and keep it level. Legs look longer.")
    ])

    public static let sitting = PoseSet(name: "Sitting", tips: [
        PoseTip(title: "Sit on the front edge", how: "Perch forward, back straight. Slumping into a chair adds weight."),
        PoseTip(title: "Angle the knees", how: "Knees turned away from the camera, never pointed straight at the lens."),
        PoseTip(title: "Lean in slightly", how: "Lean toward the camera from the hips for engagement."),
        PoseTip(title: "Shoot from their eye level", how: "Crouch so the lens is at their eye height.")
    ])

    public static let couple = PoseSet(name: "Two people", tips: [
        PoseTip(title: "Close the gap", how: "Shoulders touching or overlapping. Space between people reads as distance."),
        PoseTip(title: "Heads at different heights", how: "The taller one leans in or the other stands on a step."),
        PoseTip(title: "Look at each other", how: "One shot to camera, then one looking at each other and laughing."),
        PoseTip(title: "Walk together", how: "Hold hands and walk toward the camera. Burst.")
    ])

    public static let group = PoseSet(name: "Group", tips: [
        PoseTip(title: "Tight and layered", how: "Tallest in the back and middle, shoulders overlapping, no gaps."),
        PoseTip(title: "Stagger heads", how: "Mix sitting, leaning and standing so heads form triangles, not a line."),
        PoseTip(title: "Nobody at the edge", how: "Leave room at the sides. Wide lenses stretch people at the edges."),
        PoseTip(title: "Count and burst", how: "Say 'three, two, one' and burst on one. The app keeps the frame where everyone's eyes are open."),
        PoseTip(title: "Lens at eye level", how: "Hold the phone at the group's eye level, not above it.")
    ])

    public static let travel = PoseSet(name: "Travel", tips: [
        PoseTip(title: "Small person, big place", how: "Put them on a third line, small in the frame, with the landmark filling the rest."),
        PoseTip(title: "Back to camera", how: "They look out at the view. Works when the place is the story."),
        PoseTip(title: "Use a frame", how: "Shoot through an arch, doorway or branches to frame them."),
        PoseTip(title: "Leading lines", how: "Stand them where a road, rail or shoreline leads the eye to them."),
        PoseTip(title: "Clear the head", how: "Check nothing grows out of their head: poles, trees, signs."),
        PoseTip(title: "Golden hour", how: "The hour after sunrise and before sunset gives warm, soft, flattering light.")
    ])

    public static let scene = PoseSet(name: "Scenes", tips: [
        PoseTip(title: "Level the horizon", how: "Watch the level bar. A tilted sea or skyline looks like a mistake."),
        PoseTip(title: "Keep verticals vertical", how: "Hold the phone upright for buildings. Step back rather than tilt up."),
        PoseTip(title: "Foreground interest", how: "Get low and include something close: flowers, rocks, a railing."),
        PoseTip(title: "Thirds", how: "Horizon on the upper or lower third, not the middle, unless it is a reflection."),
        PoseTip(title: "Expose for the sky", how: "Tap the bright sky so it keeps its color. Shadows can be lifted later.")
    ])
}
