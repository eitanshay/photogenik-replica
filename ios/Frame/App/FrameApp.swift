import SwiftUI

@main
struct FrameApp: App {
    @State private var settings: SettingsStore
    @State private var session: CoachSession

    init() {
        let s = SettingsStore()
        _settings = State(initialValue: s)
        _session = State(initialValue: CoachSession(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            CameraScreen()
                .environment(settings)
                .environment(session)
                .preferredColorScheme(.dark)
        }
    }
}
