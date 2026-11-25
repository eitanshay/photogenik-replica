import CoreLocation
import UIKit
import SwiftUI

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
    var symbol: String {
        switch self {
        case .coffee: return "cup.and.saucer.fill"
        case .food: return "fork.knife"
        case .restroom: return "toilet.fill"
        }
    }
    var hint: String {
        switch self {
        case .coffee: return "the best one"
        case .food: return "Michelin first"
        case .restroom: return "the nearest"
        }
    }
}

struct NowScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var need: Need?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if model.locationStatus != .authorizedAlways { permissionCard }
                    HStack(spacing: 10) {
                        ForEach([Need.coffee, .food, .restroom]) { n in
                            NeedTile(need: n) { need = n }
                        }
                    }
                    NowPlayingBar()
                    nearbySection
                }
                .padding(.horizontal, ES.gutter)
                .padding(.bottom, 30)
            }
            .background(ES.base.ignoresSafeArea())
            .refreshable { await model.becameActive() }
            .sheet(item: $need) { n in
                ResultsSheet(need: n)
                    .presentationDetents([.large])
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LogoMark(size: 16)
                Text("roam").font(ESFont.h2).foregroundStyle(ES.ink)
                Spacer()
                ModelTag(code: "ES-11")
            }
            HStack(spacing: 8) {
                if let c = model.city { Badge(text: c, tone: .neutral) }
                Badge(text: model.tripModeActive ? "trip mode" : "home", tone: model.tripModeActive ? .signal : .neutral)
                if let g = model.goldenText { Badge(text: g, tone: .warn) }
            }
        }
        .padding(.top, 8)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Alerts need Always location").font(ESFont.sans(17, .semibold)).foregroundStyle(ES.ink)
            Text("roam uses geofences and cell-tower updates, not GPS tracking, so the battery cost is small. iOS only wakes the app near your places if location is set to Always.")
                .font(ESFont.small).foregroundStyle(ES.ink2)
            Button(model.locationStatus == .notDetermined ? "Allow location" : "Open Settings") {
                if model.locationStatus == .notDetermined { LocationEngine.shared.requestWhenInUse() }
                else if model.locationStatus == .authorizedWhenInUse { LocationEngine.shared.requestAlways() }
                else if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }
            .buttonStyle(PillButtonStyle(kind: .primary, size: .sm))
        }
        .raisedSurface()
    }

    private var nearbySection: some View {
        let items = model.nearby().map { NearbyItem(place: $0.0, distance: $0.1) }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Near you", trailing: items.isEmpty ? nil : "\(items.count)")
            if items.isEmpty {
                Text(model.here == nil ? "Waiting for your location." :
                        "Nothing saved or notable within a short walk. Import your Google Maps lists in Places, or turn on trip mode to discover sights.")
                    .font(ESFont.small).foregroundStyle(ES.ink2)
                    .raisedSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        Button { model.detailPlaceID = item.place.id } label: {
                            PlaceRow(place: item.place, distance: item.distance, metric: settings.metric)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if item.id != items.last?.id { Divider().overlay(ES.lineSoft) }
                    }
                }
                .raisedSurface(padding: 14)
            }
        }
    }
}

struct NeedTile: View {
    let need: Need
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: need.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(need == .restroom ? ES.ink : ES.onSignal)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: ES.radiusMd, style: .continuous)
                        .fill(need == .restroom ? ES.base : ES.signal))
                VStack(alignment: .leading, spacing: 2) {
                    Text(need.title).font(ESFont.sans(17, .semibold)).foregroundStyle(ES.ink)
                    Text(need.hint).font(ESFont.mono(10)).foregroundStyle(ES.ink3).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: ES.radiusXl, style: .continuous).fill(ES.paper))
        }
        .buttonStyle(TilePress())
        .accessibilityLabel("\(need.title), \(need.hint)")
    }
}

struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(ES.easeFast, value: configuration.isPressed)
    }
}

struct NearbyItem: Identifiable {
    let place: Place
    let distance: Double
    var id: String { place.id }
}
