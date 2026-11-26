import GoogleMaps
import MapKit
import SwiftUI

/// All your places on a map: saved (orange), sights (ink), scenic (amber). Google Maps when a Google key
/// is set (Maps SDK for iOS enabled on it), Apple Maps otherwise so the tab is never blank.
struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var show: Set<PlaceKind> = [.saved, .attraction, .scenic]

    private var places: [Place] {
        model.library.places.filter { p in
            guard p.isResolved, !p.muted else { return false }
            if p.scenic && show.contains(.scenic) { return true }
            return show.contains(p.kind)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if settings.hasGoogleKey {
                    GoogleMapView(places: places, center: model.here, apiKey: settings.googleMapsKey) { id in
                        model.detailPlaceID = id
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    AppleMapView(places: places) { id in model.detailPlaceID = id }
                        .ignoresSafeArea(edges: .bottom)
                }
                HStack(spacing: 8) {
                    chip(.saved, "saved")
                    chip(.attraction, "sights")
                    chip(.scenic, "scenic")
                    Spacer()
                    Text("\(places.count)").font(ESFont.mono(12, .bold)).foregroundStyle(ES.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(ES.paper))
                }
                .padding(.horizontal, ES.gutter)
                .padding(.top, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func chip(_ kind: PlaceKind, _ title: String) -> some View {
        TagChip(title: title, selected: show.contains(kind)) {
            if show.contains(kind) { show.remove(kind) } else { show.insert(kind) }
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}

enum MapColors {
    static func color(for p: Place) -> UIColor {
        if p.kind == .saved { return UIColor(hex: 0xF0662A) }
        if p.kind == .scenic || p.scenic { return UIColor(hex: 0xC98A12) }
        return UIColor(hex: 0x1D1D1B)
    }
}

// MARK: - Google Maps

struct GoogleMapView: UIViewRepresentable {
    let places: [Place]
    let center: Coordinate?
    let apiKey: String
    var onSelect: (String) -> Void

    private static var keyProvided = false

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> GMSMapView {
        if !Self.keyProvided {
            GMSServices.provideAPIKey(apiKey)
            Self.keyProvided = true
        }
        let options = GMSMapViewOptions()
        let c = center ?? places.first?.coordinate ?? Coordinate(lat: 37.4419, lng: -122.143)
        options.camera = GMSCameraPosition(latitude: c.lat, longitude: c.lng, zoom: center == nil ? 11 : 14)
        let map = GMSMapView(options: options)
        map.isMyLocationEnabled = true
        map.settings.myLocationButton = true
        map.settings.compassButton = true
        map.padding = UIEdgeInsets(top: 56, left: 0, bottom: 8, right: 0)
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        let ids = places.map { "\($0.id)|\($0.kind.rawValue)|\($0.scenic)" }
        guard ids != context.coordinator.shownIDs else { return }
        context.coordinator.shownIDs = ids
        map.clear()
        for p in places {
            guard let c = p.coordinate else { continue }
            let m = GMSMarker(position: c.cl)
            m.title = p.name
            m.snippet = [p.note, p.blurb, p.lists.first].compactMap { $0 }.first(where: { !$0.isEmpty }) ?? p.kind.label
            m.icon = GMSMarker.markerImage(with: MapColors.color(for: p))
            m.userData = p.id
            m.map = map
        }
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var onSelect: (String) -> Void
        var shownIDs: [String] = []

        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }

        func mapView(_ mapView: GMSMapView, didTapInfoWindowOf marker: GMSMarker) {
            if let id = marker.userData as? String { onSelect(id) }
        }
    }
}

// MARK: - Apple Maps fallback

struct AppleMapView: View {
    let places: [Place]
    var onSelect: (String) -> Void
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(places) { p in
                if let c = p.coordinate {
                    Annotation(p.name, coordinate: c.cl) {
                        Button { onSelect(p.id) } label: {
                            Circle().fill(Color(uiColor: MapColors.color(for: p)))
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }
}
