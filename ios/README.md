# frame for iOS (ES-10)

A native camera that coaches you while you shoot. It reads the live view about ten times a second and tells you the one thing that would most improve the photo right now, with an arrow on the viewfinder, a line of text, and (optionally) a voice. When you want a second opinion, the **director** sends one frame to Gemini and comes back with specific moves for you and your subject.

Live coaching runs entirely on the phone (Apple Vision, CoreMotion). Nothing leaves the device unless you tap **director**.

## What it coaches

Each cue has a severity (fix, improve, nice), says who has to act (you, the subject or the camera), and some carry a one-tap fix.

| Mode | What it checks |
| --- | --- |
| **Selfie** (front camera) | Phone height and tilt (above eye level, angled down), arm's length (wide-lens nose distortion), eyes on the upper third, head tilt, a slight three-quarter turn toward your better side, chin up or down, backlight and face in shadow, hard side light, something growing out of your head, busy background |
| **Portrait** (1 to 2 people, rear camera) | Level, camera height (waist height for full body, eye level for faces), crops at knees, feet and arms, headroom, 0.5x on people, step back and use 2x, square shoulders, arms glued to the body, chin, backlight with one-tap "expose for the face", sun behind the subject, poles and horizons through heads (with which way to step), clutter, small subject on a third line |
| **Group** | Level, heads cut, people at the frame edge, gaps between people, a hidden back row, everyone's head on one line, shooting down on a group, blinks |
| **Scene** | Level to 1.5°, converging verticals, blown sky, low light, shooting into the sun, subject on a third line |

**Auto** picks the mode from the camera and the number of people in frame.

Also on screen: a thirds grid, a level bar that turns green when straight, brackets on faces (amber with "eyes closed"), crop marks on cut joints, red zones on background collisions, a target zone for where to put the subject, and a readiness ring around the shutter that fills as the shot improves.

## Capture

- **Smart burst.** Each press takes a short burst (5 by default) and keeps the frame where everyone's eyes are open and the face is sharpest. The best one saves to Photos, in a "frame" album, with location. Tap the thumbnail to see all frames and save others.
- **Auto** (A button): shoots on its own once the shot has been ready for 0.7 seconds.
- **Hands-free** (hand button): show an open palm to the camera to start a 3 second countdown. Good for a phone propped on a wall.
- **Timer**: 3 or 10 seconds.
- **Voice**: speaks the top cue, the countdown, and "Looks good" (default: selfies only, since you cannot read the screen at arm's length).

## Light

With location on, the badge in the top bar shows the light: golden hour countdown ("golden in 1h 12m", "golden · 18m left"), daylight, harsh sun or night. The sun's direction relative to where the lens points (from the compass) feeds the coaching: backlit subjects get "expose for their face" instead of "turn around", midday hard light gets "find open shade", scenes get "shooting into the sun".

## Director (Gemini)

Tap **director**. One frame plus context (mode, lens, tilt, people count, local time, sun direction, place name) goes to Gemini. It answers with a headline, up to three ordered moves with who does each, pose tips, light and background notes, a lens suggestion (one tap to switch), a creative alternative, and a box on the viewfinder showing where the subject should sit. It uses the same Gemini key setup as polish; paste the key in Settings once (it lives in the Keychain).

## Layout

| Path | What |
| --- | --- |
| `Frame.xcodeproj` | Generated project, one app target, shared scheme `Frame` |
| `Frame/App` | App entry, settings, the coaching session (camera, sensors, capture, voice, director) |
| `Frame/Camera` | Capture session, lenses and rotation; live Vision analysis; burst ranking |
| `Frame/Platform` | Motion and location, Photos saving, Keychain, voice, haptics |
| `Frame/UI` | Camera screen, overlays, coaching card, director panel, sheets, Eitan Shay design system |
| `FrameCore` | The rules engine, sun position, image metrics, smoothing, burst ranking, director prompt and parsing, Gemini client. Compiled into the app and unit-tested with `swift test` (54 tests, runs on Linux too) |
| `scripts/generate_project.rb` | Regenerates the Xcode project (`gem install xcodeproj && ruby scripts/generate_project.rb`) |

## First build (Codemagic to TestFlight)

Same setup as polish and BloomTrack. You only do it once.

1. **Register the bundle ID.** Apple Developer portal, Identifiers, add an App ID `com.eitanshay.frame`. No extra capabilities.
2. **Create the profile.** Profiles, add an App Store distribution profile for that ID with the distribution certificate Codemagic already holds.
3. **Fetch it into Codemagic.** Team settings, codemagic.yaml settings, Code signing identities, iOS provisioning profiles, Fetch profiles, pick the frame profile.
4. **Create the app record.** App Store Connect, Apps, + New App, iOS, bundle ID from step 1. The store name must be unique, so use something like "frame ES-10" (the home screen still says "frame"). Copy the numeric **Apple ID** from General, App Information.
5. **Set `APP_STORE_APPLE_ID`** in `codemagic.yaml` at the repo root to that number. Until you do, every build is numbered 1 and later uploads will be rejected as duplicates.
6. **Add the repo to Codemagic** (eitanshay/photogenik-replica) if it is not there, then push or start "frame iOS to TestFlight" by hand. Builds run on pushes to `main` that touch `ios/` or `codemagic.yaml`.
7. **Install** from TestFlight once Apple finishes processing (10 to 30 minutes). Add yourself to Internal Testing if needed.
8. **First launch.** Allow camera, location (for the sun) and Photos. Paste your Gemini key in Settings for the director.

## Known limits

- Built without a Mac in the loop: the coaching engine is tested, but the camera and Vision code compile for the first time on Codemagic. Expect one or two fix-up builds.
- Thresholds (face size, chin, light ratios, clutter) are first guesses from photography rules. They need tuning on real shots; all of them live in `FrameCore/Sources/FrameCore/Coach.swift`.
- Head turn uses only the size of the turn, not its direction, because detectors disagree on the sign. "Your better side" changes the wording, not the check.
- Chin up or down is estimated from where the nose tip sits between eyes and mouth. It is approximate, especially in steep selfies.
- The selfie camera is analysed in portrait only. Landscape works for the rear camera (overlays rotate), but the coaching card stays upright.
- Mergers (poles, horizons through heads) need a clear background line and a person mask, so they are conservative by design.
