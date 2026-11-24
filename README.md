# Photogenik replica

A single-file web replica of the Photogenik pose and photo coach app, built for testing.

- Live viewfinder with pose silhouette overlays (Selfie, Standing, Sitting, Mirror)
- On-device body and face landmarking (MediaPipe Tasks Vision, loaded from CDN)
- Head-angle coaching cues, "Find your angles" scan, hands-free timer and auto-capture
- Best-shot scoring: sharpness, exposure, eyes open, expression, head angle, framing, pose match

Everything runs in the browser. No photo or face data leaves the device.

Open `index.html` over HTTPS (or localhost); camera access requires a secure context.

## Native iOS app: frame (ES-10)

`ios/` holds **frame**, a native SwiftUI camera that coaches framing, camera angle, light and pose in real time with Apple Vision, picks the best frame of each burst, and can ask a Gemini "director" for scene-specific advice. It builds to TestFlight through Codemagic (`codemagic.yaml`). See [ios/README.md](ios/README.md).
