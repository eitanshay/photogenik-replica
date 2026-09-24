# Photogenik replica

A single-file web replica of the Photogenik pose and photo coach app, built for testing.

- Live viewfinder with pose silhouette overlays (Selfie, Standing, Sitting, Mirror)
- On-device body and face landmarking (MediaPipe Tasks Vision, loaded from CDN)
- Head-angle coaching cues, "Find your angles" scan, hands-free timer and auto-capture
- Best-shot scoring: sharpness, exposure, eyes open, expression, head angle, framing, pose match

Everything runs in the browser. No photo or face data leaves the device.

Open `index.html` over HTTPS (or localhost); camera access requires a secure context.
