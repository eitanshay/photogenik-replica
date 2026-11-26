import CoreLocation
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var model = model
        Group {
            if settings.onboarded {
                // One screen: the map. Everything else opens from its menu.
                MapHome()
                    .tint(ES.ink)
            } else {
                OnboardingView()
            }
        }
        .sheet(item: $model.sheet) { s in
            Group {
                switch s {
                case .places: PlacesScreen()
                case .trips: TripsScreen()
                case .settings: SettingsScreen()
                }
            }
            .presentationDragIndicator(.visible)
            .sheet(item: detailBinding(whenSheet: true)) { box in
                PlaceDetailView(placeID: box.id)
                    .presentationDetents([.large])
            }
        }
        // A place page opens over the map, or over Places or Trips when one of those is up.
        .sheet(item: detailBinding(whenSheet: false)) { box in
            PlaceDetailView(placeID: box.id)
                .presentationDetents([.large])
        }
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                ToastView(message: t)
                    .padding(.bottom, 230)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: t) {
                        try? await Task.sleep(for: .seconds(3.5))
                        withAnimation(ES.ease) { model.toast = nil }
                    }
            }
        }
        .animation(ES.ease, value: model.toast)
    }
}

extension RootView {
    func detailBinding(whenSheet: Bool) -> Binding<IDBox?> {
        Binding(get: {
            guard (model.sheet != nil) == whenSheet else { return nil }
            return model.detailPlaceID.map(IDBox.init)
        }, set: { model.detailPlaceID = $0?.id })
    }
}

struct IDBox: Identifiable, Hashable {
    let id: String
}

// MARK: - Shared rows

extension PlaceKind {
    var symbol: String {
        switch self {
        case .saved: return "bookmark.fill"
        case .attraction: return "sparkles"
        case .scenic: return "camera.fill"
        }
    }
}

struct PlaceRow: View {
    let place: Place
    let distance: Double?
    var metric: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.scenic && place.kind == .saved ? "camera.fill" : place.kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(place.kind == .saved ? ES.onSignal : ES.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(place.kind == .saved ? ES.signal : ES.base))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(ESFont.sans(16, .semibold)).foregroundStyle(ES.ink).lineLimit(1)
                Text(subtitle).font(ESFont.small).foregroundStyle(ES.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let d = distance {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Geo.walkingMinutes(d)) min").font(ESFont.mono(12, .bold)).foregroundStyle(ES.ink)
                    Text(Geo.formatDistance(d, metric: metric)).font(ESFont.mono(11)).foregroundStyle(ES.ink3)
                }
            } else if !place.isResolved {
                Badge(text: "not on map", tone: .warn)
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if let n = place.note, !n.isEmpty { return n }
        if let b = place.blurb, !b.isEmpty { return b.capitalizedFirst }
        if let l = place.lists.first { return l }
        return place.kind.label
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String?
    var body: some View {
        HStack {
            MonoLabel(text)
            Spacer()
            if let t = trailing { MonoLabel(t, color: ES.ink3) }
        }
        .padding(.horizontal, 4)
    }
}

/// Mini player shown while a story is playing.
struct NowPlayingBar: View {
    @Environment(AppModel.self) private var model
    @Environment(Narrator.self) private var narrator

    var body: some View {
        if let id = narrator.speakingPlaceID {
            HStack(spacing: 12) {
                Button { narrator.togglePause() } label: {
                    Image(systemName: narrator.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ES.onSignal)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(ES.signal))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(narrator.isPaused ? "Resume" : "Pause")
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.place(id)?.name ?? "Story").font(ESFont.sans(15, .semibold)).foregroundStyle(ES.ink).lineLimit(1)
                    ProgressView(value: narrator.progress).tint(ES.signal)
                }
                Button { narrator.stop() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(ES.ink2)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop")
            }
            .raisedSurface(padding: 12)
            .onTapGesture { model.detailPlaceID = id }
        }
    }
}
