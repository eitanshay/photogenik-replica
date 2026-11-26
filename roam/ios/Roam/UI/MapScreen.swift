import GoogleMaps
import MapKit
import Observation
import SwiftUI

// The whole app is this map. Chips along the top choose what is on it: your saved places, sights and
// scenic spots from your library, and on-demand searches for coffee, food and restrooms around you.
// Tap a pin for a card with distance, rating or rank, and a few words.

// MARK: - Look of each category

extension PinCategory {
    var symbol: String {
        switch self {
        case .saved: return "bookmark.fill"
        case .sight: return "building.columns.fill"
        case .scenic: return "camera.fill"
        case .coffee: return "cup.and.saucer.fill"
        case .food: return "fork.knife"
        case .restroom: return "toilet.fill"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .saved: return UIColor(hex: 0xF0662A)
        case .sight: return UIColor(hex: 0x1D1D1B)
        case .scenic: return UIColor(hex: 0xC98A12)
        case .coffee: return UIColor(hex: 0x7A4A2B)
        case .food: return UIColor(hex: 0xC8372D)
        case .restroom: return UIColor(hex: 0x2F6FB0)
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    var need: Need? {
        switch self {
        case .coffee: return .coffee
        case .food: return .food
        case .restroom: return .restroom
        default: return nil
        }
    }
}

/// Coffee, food and restroom searches (also used by the list view of results).
enum Need: String, Identifiable {
    case coffee, food, restroom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .coffee: return "Coffee"
        case .food: return "Food"
        case .restroom: return "Restroom"
        }
    }
}

/// Round marker images, drawn once per look and cached.
enum PinImage {
    private static var cache: [String: UIImage] = [:]

    static func image(_ c: PinCategory, michelin: Bool, selected: Bool) -> UIImage {
        let key = "\(c.rawValue)-\(michelin)-\(selected)"
        if let img = cache[key] { return img }
        let d: CGFloat = selected ? 42 : 30
        let pad: CGFloat = 4
        let size = CGSize(width: d + pad * 2, height: d + pad * 2)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(x: pad, y: pad, width: d, height: d)
            let cg = ctx.cgContext
            cg.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            cg.setFillColor(c.uiColor.cgColor)
            cg.fillEllipse(in: rect)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            cg.setStrokeColor((selected ? UIColor(hex: 0xF0662A) : UIColor.white).cgColor)
            cg.setLineWidth(selected ? 3.5 : 2.5)
            cg.strokeEllipse(in: rect.insetBy(dx: 1.25, dy: 1.25))
            let name = michelin ? "star.fill" : c.symbol
            let config = UIImage.SymbolConfiguration(pointSize: selected ? 18 : 13, weight: .bold)
            if let sym = UIImage(systemName: name, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let s = sym.size
                sym.draw(in: CGRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height))
            }
        }
        cache[key] = img
        return img
    }
}

// MARK: - State of the map

/// Where the camera should go: one pin, or a set of points to fit. A new id asks the map to move.
struct MapFocus: Equatable {
    var id = UUID()
    var points: [Coordinate]
}

@MainActor
@Observable
final class MapModel {
    var layers: Set<PinCategory> {
        didSet { UserDefaults.standard.set(layers.filter { !$0.isSearch }.map(\.rawValue), forKey: "mapLayers") }
    }
    var results: [PinCategory: [RankedVenue]] = [:]
    var loading: Set<PinCategory> = []
    var selectedID: String?
    var focus: MapFocus?

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "mapLayers")
        layers = Set((saved ?? ["saved", "sight", "scenic"]).compactMap(PinCategory.init(rawValue:)))
    }

    func pins(_ model: AppModel) -> [Pin] {
        var out: [Pin] = []
        for p in model.library.places where p.isResolved && !p.muted && p.coordinate != nil {
            if layers.contains(PinCategory.of(p)) { out.append(Pin(place: p)) }
        }
        for c in [PinCategory.coffee, .food, .restroom] where layers.contains(c) {
            let list = Array((results[c] ?? []).prefix(12))
            for (i, r) in list.enumerated() {
                out.append(Pin(ranked: r, category: c, rank: i + 1, of: list.count))
            }
        }
        return out
    }

    func toggle(_ c: PinCategory, model: AppModel) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if layers.contains(c) {
            layers.remove(c)
            if let id = selectedID, !pins(model).contains(where: { $0.id == id }) { selectedID = nil }
            return
        }
        layers.insert(c)
        if c.isSearch {
            Task { await search(c, model: model) }
        } else {
            let pts = pins(model).filter { $0.category == c }.map(\.coordinate)
            if pts.isEmpty {
                model.toast = c == .saved ? "No saved places yet. Add them from the menu, Places." : "None nearby yet: roam finds them as you move."
            }
        }
    }

    /// Runs a coffee, food or restroom search where you are, then shows the best pick.
    func search(_ c: PinCategory, model: AppModel) async {
        guard let need = c.need else { return }
        loading.insert(c)
        defer { loading.remove(c) }
        do {
            let loc = try await LocationEngine.shared.currentLocation(maxAge: 60)
            let here = loc.coord
            model.here = here
            let settings = model.settings
            let service = NearbyService(googleKey: settings.googleMapsKey)
            let found: [RankedVenue]
            switch need {
            case .coffee: found = try await service.coffee(at: here)
            case .food:
                found = try await service.food(at: here, budget: Budget(rawValue: settings.lastBudget) ?? .mid,
                                               cuisine: Cuisine(rawValue: settings.lastCuisine) ?? .any)
            case .restroom: found = await service.restroom(at: here)
            }
            guard layers.contains(c) else { return }
            results[c] = found
            if found.isEmpty {
                model.toast = c == .restroom ? "No mapped restrooms nearby" : "Nothing open that matches nearby"
                return
            }
            let best = Pin(ranked: found[0], category: c, rank: 1, of: min(12, found.count))
            selectedID = best.id
            focus = MapFocus(points: [here] + found.prefix(5).map(\.venue.coordinate))
        } catch {
            model.toast = error.localizedDescription
        }
    }

    func select(_ pin: Pin?) {
        selectedID = pin?.id
        if let pin { focus = MapFocus(points: [pin.coordinate]) }
    }
}

// MARK: - The screen

struct MapHome: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var map = MapModel()
    @State private var listNeed: Need?

    var body: some View {
        let pins = map.pins(model)
        let selected = pins.first { $0.id == map.selectedID }
        ZStack {
            Group {
                if settings.hasGoogleKey {
                    GoogleMapView(pins: pins, selectedID: map.selectedID, focus: map.focus, center: model.here,
                                  apiKey: settings.googleMapsKey) { id in
                        map.selectedID = id
                    }
                } else {
                    AppleMapView(pins: pins, selectedID: map.selectedID, focus: map.focus) { id in
                        map.selectedID = id
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                topBar
                if map.layers.contains(.food) { foodFilters }
                statusRow
                Spacer()
                NowPlayingBar()
                if let selected {
                    PinCard(pin: selected, siblings: PinText.ordered(pins, category: selected.category, from: model.here),
                            onSelect: { map.select($0) },
                            onList: { listNeed = selected.category.need },
                            onClose: { map.selectedID = nil })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(selected.id)
                } else if pins.isEmpty {
                    hint
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .animation(ES.ease, value: map.selectedID)
        }
        .sheet(item: $listNeed) { n in
            ResultsSheet(need: n).presentationDetents([.large])
        }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button { model.sheet = .places } label: { Label("Places and import", systemImage: "bookmark") }
                Button { model.sheet = .trips } label: { Label("Trips", systemImage: "suitcase") }
                Button { model.sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ES.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(ES.paper))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            }
            .accessibilityLabel("Menu")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PinCategory.allCases) { c in
                        LayerChip(category: c, on: map.layers.contains(c), loading: map.loading.contains(c)) {
                            map.toggle(c, model: model)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 4)
            }
        }
    }

    private var foodFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Budget.allCases, id: \.self) { b in
                    SmallChip(title: b.label, on: settings.lastBudget == b.rawValue) {
                        settings.lastBudget = b.rawValue
                        Task { await map.search(.food, model: model) }
                    }
                }
                Divider().frame(height: 18)
                ForEach(Cuisine.allCases, id: \.self) { c in
                    SmallChip(title: c.label, on: settings.lastCuisine == c.rawValue) {
                        settings.lastCuisine = c.rawValue
                        Task { await map.search(.food, model: model) }
                    }
                }
            }
            .padding(.leading, 48)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        let needsLocation = model.locationStatus != .authorizedAlways
        if needsLocation || model.goldenText != nil {
            HStack(spacing: 6) {
                if needsLocation {
                    Button {
                        if model.locationStatus == .notDetermined { LocationEngine.shared.requestWhenInUse() }
                        else if model.locationStatus == .authorizedWhenInUse { LocationEngine.shared.requestAlways() }
                        else if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    } label: {
                        Label("Allow Always location for alerts", systemImage: "location.fill")
                            .font(ESFont.sans(12, .semibold))
                            .foregroundStyle(ES.onSignal)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(ES.signal))
                    }
                    .buttonStyle(.plain)
                }
                if let g = model.goldenText {
                    Label(g, systemImage: "sun.horizon.fill")
                        .font(ESFont.mono(11, .medium))
                        .foregroundStyle(ES.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(ES.paper))
                }
                Spacer()
            }
            .padding(.leading, 48)
        }
    }

    private var hint: some View {
        Text("Tap Coffee, Food or Restroom to search around you, or turn on Saved, Sights and Scenic.")
            .font(ESFont.small)
            .foregroundStyle(ES.ink2)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: ES.radiusLg, style: .continuous).fill(ES.paper))
    }
}

struct LayerChip: View {
    let category: PinCategory
    let on: Bool
    let loading: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if loading {
                    ProgressView().controlSize(.mini).tint(on ? .white : category.color)
                } else {
                    Image(systemName: category.symbol).font(.system(size: 12, weight: .bold))
                }
                Text(category.label).font(ESFont.sans(14, .semibold))
            }
            .foregroundStyle(on ? Color.white : ES.ink)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(on ? category.color : ES.paper))
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.label)
        .accessibilityAddTraits(on ? .isSelected : [])
        .animation(ES.easeFast, value: on)
    }
}

struct SmallChip: View {
    let title: String
    let on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ESFont.sans(12, .semibold))
                .foregroundStyle(on ? ES.panel : ES.ink)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(on ? ES.ink : ES.paper))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - The card

struct PinCard: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    let pin: Pin
    let siblings: [Pin]
    var onSelect: (Pin) -> Void
    var onList: () -> Void
    var onClose: () -> Void

    private var place: Place? { model.place(pin.placeID) }
    private var index: Int? { siblings.firstIndex { $0.id == pin.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: pin.isMichelin ? "star.fill" : pin.category.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(pin.category.color))
                VStack(alignment: .leading, spacing: 3) {
                    Text(pin.name).font(ESFont.sans(18, .semibold)).foregroundStyle(ES.ink).lineLimit(2)
                    metaLine
                }
                Spacer(minLength: 4)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(ES.ink2)
                        .frame(width: 30, height: 30).background(Circle().fill(ES.base))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            if let w = pin.words {
                Text(w).font(ESFont.sans(14)).foregroundStyle(ES.ink2).lineLimit(2)
            }
            HStack(spacing: 8) {
                Button {
                    Navigator.walk(to: pin.coordinate, name: pin.name, using: settings.navApp)
                } label: {
                    Label(distanceText ?? "Walk there", systemImage: "figure.walk")
                }
                .buttonStyle(PillButtonStyle(kind: .primary, size: .sm))
                if let p = place {
                    if p.kind != .saved || p.wikipediaTitle != nil {
                        Button {
                            Task { await model.listen(p.id) }
                        } label: {
                            Label(model.isGenerating(p.id) ? "Writing…" : "Listen", systemImage: "headphones")
                        }
                        .buttonStyle(PillButtonStyle(kind: .secondary, size: .sm))
                    }
                    Button("More") { model.detailPlaceID = p.id }
                        .buttonStyle(PillButtonStyle(kind: .secondary, size: .sm))
                } else if let v = pin.venue {
                    Button {
                        model.addManual(name: v.name, at: v.coordinate, note: pin.reason)
                        model.toast = "Saved \(v.name)"
                    } label: {
                        Label("Save", systemImage: "bookmark")
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary, size: .sm))
                    if pin.category.need != nil {
                        Button("List", action: onList).buttonStyle(PillButtonStyle(kind: .secondary, size: .sm))
                    }
                }
                Spacer(minLength: 0)
                if let i = index, siblings.count > 1 {
                    stepper(i)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: ES.radiusXl, style: .continuous).fill(ES.paper))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 4)
    }

    private var distanceText: String? {
        guard let h = model.here else { return nil }
        let d = Geo.distance(h, pin.coordinate)
        return "\(Geo.walkingMinutes(d)) min · \(Geo.formatDistance(d, metric: settings.metric))"
    }

    private var metaLine: some View {
        var bits: [String] = []
        if let r = PinText.rank(pin) { bits.append(r) }
        if let v = pin.venue {
            if let m = v.michelin { bits.append(m.label) }
            if let r = PinText.rating(v) { bits.append(r) }
            if let p = PinText.price(v) { bits.append(p) }
        } else if let p = place {
            bits.append(p.kind == .saved ? (p.lists.first ?? "Saved") : (pin.category == .scenic ? "Scenic spot" : "Worth a look"))
            if p.kind != .saved {
                let stars = max(1, min(3, Int((p.score * 3).rounded(.up))))
                bits.append(String(repeating: "★", count: stars))
            }
        }
        let open = pin.venue?.openNow
        return HStack(spacing: 6) {
            Text(bits.joined(separator: " · ")).font(ESFont.mono(11, .medium)).foregroundStyle(ES.ink2).lineLimit(1)
            if let open {
                Text(open ? "open" : "closed").font(ESFont.mono(10, .bold))
                    .foregroundStyle(open ? ES.badgeOKFG : ES.badgeErrorFG)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(open ? ES.badgeOKBG : ES.badgeErrorBG))
            }
        }
    }

    private func stepper(_ i: Int) -> some View {
        HStack(spacing: 2) {
            Button { onSelect(siblings[(i - 1 + siblings.count) % siblings.count]) } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 32)
            }
            .accessibilityLabel("Previous")
            Text("\(i + 1)/\(siblings.count)").font(ESFont.mono(11, .bold)).foregroundStyle(ES.ink2)
            Button { onSelect(siblings[(i + 1) % siblings.count]) } label: {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 32)
            }
            .accessibilityLabel("Next")
        }
        .buttonStyle(.plain)
        .foregroundStyle(ES.ink)
    }
}

// MARK: - Google Maps

struct GoogleMapView: UIViewRepresentable {
    let pins: [Pin]
    let selectedID: String?
    let focus: MapFocus?
    let center: Coordinate?
    let apiKey: String
    var onSelect: (String?) -> Void

    private static var keyProvided = false

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> GMSMapView {
        if !Self.keyProvided {
            GMSServices.provideAPIKey(apiKey)
            Self.keyProvided = true
        }
        let options = GMSMapViewOptions()
        let c = center ?? pins.first?.coordinate ?? Coordinate(lat: 37.4419, lng: -122.143)
        options.camera = GMSCameraPosition(latitude: c.lat, longitude: c.lng, zoom: center == nil ? 12 : 15)
        let map = GMSMapView(options: options)
        map.isMyLocationEnabled = true
        map.settings.myLocationButton = true
        map.settings.compassButton = true
        map.padding = UIEdgeInsets(top: 120, left: 0, bottom: 210, right: 0)
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        let co = context.coordinator
        co.onSelect = onSelect
        // Add, update and remove markers by id instead of clearing, so the map does not flash.
        var keep = Set<String>()
        for p in pins {
            keep.insert(p.id)
            let selected = p.id == selectedID
            let marker = co.markers[p.id] ?? {
                let m = GMSMarker(position: p.coordinate.cl)
                m.userData = p.id
                m.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                m.map = map
                co.markers[p.id] = m
                return m
            }()
            marker.position = p.coordinate.cl
            let look = "\(p.category.rawValue)-\(p.isMichelin)-\(selected)"
            if co.looks[p.id] != look {
                marker.icon = PinImage.image(p.category, michelin: p.isMichelin, selected: selected)
                co.looks[p.id] = look
            }
            marker.zIndex = Int32(selected ? 10_000 : p.prominence * 100)
        }
        for (id, m) in co.markers where !keep.contains(id) {
            m.map = nil
            co.markers[id] = nil
            co.looks[id] = nil
        }
        if let f = focus, f.id != co.lastFocus {
            co.lastFocus = f.id
            if f.points.count == 1, let p = f.points.first {
                map.animate(to: GMSCameraPosition(latitude: p.lat, longitude: p.lng, zoom: max(map.camera.zoom, 15)))
            } else if !f.points.isEmpty {
                var b = GMSCoordinateBounds()
                for p in f.points { b = b.includingCoordinate(p.cl) }
                map.animate(with: GMSCameraUpdate.fit(b, with: UIEdgeInsets(top: 60, left: 50, bottom: 60, right: 50)))
            }
        }
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var onSelect: (String?) -> Void
        var markers: [String: GMSMarker] = [:]
        var looks: [String: String] = [:]
        var lastFocus: UUID?

        init(onSelect: @escaping (String?) -> Void) {
            self.onSelect = onSelect
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let id = marker.userData as? String { onSelect(id) }
            return true // no info window: the card shows the details
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            onSelect(nil)
        }
    }
}

// MARK: - Apple Maps fallback

struct AppleMapView: View {
    let pins: [Pin]
    let selectedID: String?
    let focus: MapFocus?
    var onSelect: (String?) -> Void
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(pins) { p in
                Annotation(p.id == selectedID ? p.name : "", coordinate: p.coordinate.cl, anchor: .center) {
                    Button { onSelect(p.id) } label: {
                        Image(uiImage: PinImage.image(p.category, michelin: p.isMichelin, selected: p.id == selectedID))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(p.name)
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .safeAreaPadding(.top, 110)
        .safeAreaPadding(.bottom, 200)
        .onChange(of: focus) { _, f in
            guard let f, !f.points.isEmpty else { return }
            let lats = f.points.map(\.lat), lngs = f.points.map(\.lng)
            let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
            let span = MKCoordinateSpan(latitudeDelta: max(0.004, (lats.max()! - lats.min()!) * 1.5),
                                        longitudeDelta: max(0.004, (lngs.max()! - lngs.min()!) * 1.5))
            withAnimation(ES.ease) { position = .region(MKCoordinateRegion(center: center, span: span)) }
        }
    }
}
