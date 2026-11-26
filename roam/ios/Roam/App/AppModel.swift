import CoreLocation
import Foundation
import Observation
import UIKit

/// Secondary screens, opened from the map's menu.
enum AppSheet: String, Identifiable {
    case places, trips, settings
    var id: String { rawValue }
}

/// The app's brain: owns the place library, reacts to location wake-ups, decides what to notify.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let settings = SettingsStore()
    let store: PlaceFileStore
    var library: PlaceLibrary

    var here: Coordinate?
    var city: String?
    var trips: [Trip] = []
    var sheet: AppSheet?
    var detailPlaceID: String?
    var autoplayPlaceID: String?
    var toast: String?
    var importStatus: String?
    var resolving = 0
    var locationStatus: CLAuthorizationStatus = .notDetermined

    private var alertLog: [AlertLogEntry]
    private var lastDiscovery: (center: Coordinate, date: Date)?
    private var cityCenter: Coordinate?
    private var generating = Set<String>()

    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Roam", isDirectory: true)
    }

    private init() {
        store = PlaceFileStore(directory: Self.dataDirectory)
        library = store.loadLibrary()
        let d = UserDefaults.standard
        if let data = d.data(forKey: "alertLog"), let log = try? JSONDecoder().decode([AlertLogEntry].self, from: data) {
            alertLog = log
        } else {
            alertLog = []
        }
        if let lat = d.object(forKey: "discLat") as? Double, let lng = d.object(forKey: "discLng") as? Double,
           let t = d.object(forKey: "discDate") as? Date {
            lastDiscovery = (Coordinate(lat: lat, lng: lng), t)
        }
        SharedInbox.drain(into: &library)
    }

    // MARK: Launch wiring

    /// Called from the app delegate at every launch, including silent background relaunches by iOS.
    func bootstrap() {
        let engine = LocationEngine.shared
        engine.onMove = { [weak self] loc in self?.backgroundWork { await self?.handleMove(loc) } }
        engine.onEnter = { [weak self] id in self?.backgroundWork { await self?.handleEnter(id) } }
        engine.onAuthChange = { [weak self] s in
            self?.locationStatus = s
            if s == .authorizedAlways, let l = LocationEngine.shared.lastLocation {
                self?.backgroundWork { await self?.handleMove(l) }
            }
        }
        locationStatus = engine.status
        engine.start()
        if let l = engine.lastLocation { here = l.coord }
    }

    /// Gives async work up to ~30 s when iOS woke us in the background.
    func backgroundWork(_ work: @escaping @MainActor () async -> Void) {
        let box = TaskBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: "roam.work") {
            box.end()
        }
        Task { @MainActor in
            await work()
            box.end()
        }
    }

    /// Foreground: pick up share-sheet saves, refresh location once, re-plan.
    func becameActive() async {
        let added = SharedInbox.drain(into: &library)
        if !added.isEmpty {
            save()
            toast = added.count == 1 ? "Saved from the share sheet" : "Saved \(added.count) places from the share sheet"
        }
        if let loc = try? await LocationEngine.shared.currentLocation(maxAge: 300) {
            await handleMove(loc)
        }
        await resolvePending()
    }

    // MARK: State

    var tripModeActive: Bool {
        switch settings.tripMode {
        case .on: return true
        case .off: return false
        // No home set yet: treat everywhere as a trip, so discovery works out of the box while traveling.
        case .auto: return settings.home == nil || AlertPolicy.isTripMode(here: here, home: settings.home)
        }
    }

    func save() {
        store.save(library)
    }

    private func saveLog() {
        alertLog = Array(alertLog.suffix(60))
        if let data = try? JSONEncoder().encode(alertLog) { UserDefaults.standard.set(data, forKey: "alertLog") }
    }

    func place(_ id: String?) -> Place? { id.flatMap { library.place(id: $0) } }

    func update(_ p: Place) {
        library.update(p)
        save()
    }

    func distance(to p: Place) -> Double? {
        guard let h = here, let c = p.coordinate else { return nil }
        return Geo.distance(h, c)
    }

    /// Saved and discovered places near you, nearest first.
    func nearby(within meters: Double = 3_000, limit: Int = 12) -> [(Place, Double)] {
        guard let h = here else { return [] }
        return library.places.compactMap { p -> (Place, Double)? in
            guard let c = p.coordinate, !p.muted else { return nil }
            let d = Geo.distance(h, c)
            return d <= meters ? (p, d) : nil
        }
        .sorted { a, b in
            // Saved first within a short walk, then by distance.
            let wa = a.0.kind == .saved ? a.1 * 0.7 : a.1 / (0.6 + 0.4 * a.0.score)
            let wb = b.0.kind == .saved ? b.1 * 0.7 : b.1 / (0.6 + 0.4 * b.0.score)
            return wa < wb
        }
        .prefix(limit).map { $0 }
    }

    var goldenText: String? {
        guard let h = here else { return nil }
        let now = Date()
        guard let w = Sun.goldenWindow(from: now, latitude: h.lat, longitude: h.lng) else { return nil }
        if w.start <= now { return "golden hour · \(Int(w.end.timeIntervalSince(now) / 60)) min left" }
        let mins = Int(w.start.timeIntervalSince(now) / 60)
        return mins < 180 ? "golden hour in \(mins / 60 > 0 ? "\(mins / 60)h " : "")\(mins % 60)m" : nil
    }

    private func goldenMinutes(at c: Coordinate) -> Int? {
        guard let w = Sun.goldenWindow(from: Date(), latitude: c.lat, longitude: c.lng) else { return nil }
        return max(0, Int(w.start.timeIntervalSinceNow / 60))
    }

    // MARK: Location events

    func handleMove(_ loc: CLLocation) async {
        let c = loc.coord
        here = c
        if !SharedInbox.drain(into: &library).isEmpty { save() }
        if cityCenter.map({ Geo.distance($0, c) > 5_000 }) ?? true {
            city = await Geocode.city(c)
            cityCenter = c
        }
        await refreshDiscoveryIfNeeded(at: c)
        replan(from: c, speed: loc.speed)
    }

    /// Re-arms the 19 nearest geofences, and alerts right away for places you are already standing at.
    func replan(from c: Coordinate, speed: Double? = nil) {
        let plan = GeofencePlanner.plan(from: c, places: library.places,
                                        maxDistance: 30_000, maxRegionRadius: 5_000)
        LocationEngine.shared.apply(plan)
        for id in plan.alreadyInside {
            if let p = library.place(id: id) { alertIfAllowed(p, distance: GeofencePlanner.radius(for: p) / 2, speed: speed) }
        }
    }

    func handleEnter(_ placeID: String) async {
        guard let p = library.place(id: placeID), let c = p.coordinate else { return }
        var d = GeofencePlanner.radius(for: p)
        var speed: Double?
        if let l = LocationEngine.shared.lastLocation, -l.timestamp.timeIntervalSinceNow < 120 {
            d = Geo.distance(l.coord, c)
            speed = l.speed >= 0 ? l.speed : nil
            here = l.coord
        }
        alertIfAllowed(p, distance: d, speed: speed)
    }

    private func alertIfAllowed(_ p: Place, distance: Double, speed: Double?) {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let decision = AlertPolicy.decide(place: p, now: now, hour: hour, tripMode: tripModeActive, speed: speed,
                                          log: alertLog, settings: settings.alertSettings)
        guard decision == .allow else { return }
        let golden = (p.scenic || p.kind == .scenic) ? p.coordinate.flatMap { goldenMinutes(at: $0) } : nil
        Notifier.post(AlertComposer.compose(place: p, distance: distance, metric: settings.metric, goldenStartsIn: golden), placeID: p.id)
        var q = p
        q.lastAlertAt = now
        library.update(q)
        alertLog.append(AlertLogEntry(placeID: p.id, date: now, discovery: p.isDiscovered))
        saveLog()
        save()
        // Have the story ready by the time you tap Listen.
        if q.guideScript == nil && settings.hasClaudeKey {
            Task { _ = try? await self.script(for: q) }
        }
    }

    // MARK: Discovery

    func refreshDiscoveryIfNeeded(at c: Coordinate, force: Bool = false) async {
        let wanted = tripModeActive || settings.discoverNearHome
        guard force || (wanted && (settings.discoveryEnabled || settings.scenicEnabled)) else { return }
        if !force, let last = lastDiscovery, Geo.distance(last.center, c) < 2_500, Date().timeIntervalSince(last.date) < 12 * 3_600 { return }
        let service = NearbyService(googleKey: settings.googleMapsKey)
        let found = await service.discover(at: c, lang: settings.wikiLang, includeScenic: settings.scenicEnabled)
        guard !found.isEmpty else { return }
        for p in found where settings.discoveryEnabled || p.kind == .scenic { library.upsert(p) }
        library.pruneDiscovered(around: c)
        save()
        lastDiscovery = (c, Date())
        let d = UserDefaults.standard
        d.set(c.lat, forKey: "discLat")
        d.set(c.lng, forKey: "discLng")
        d.set(Date(), forKey: "discDate")
    }

    // MARK: Saved places

    func resolvePending() async {
        let pending = library.unresolved
        guard !pending.isEmpty, resolving == 0 else { return }
        resolving = pending.count
        let service = NearbyService(googleKey: settings.googleMapsKey)
        let near = here
        for chunk in stride(from: 0, to: pending.count, by: 4).map({ Array(pending[$0..<min($0 + 4, pending.count)]) }) {
            let results = await withTaskGroup(of: Place.self) { group -> [Place] in
                for p in chunk { group.addTask { await service.resolve(p, near: near) } }
                var out: [Place] = []
                for await r in group { out.append(r) }
                return out
            }
            for r in results { library.update(r) }
            resolving = max(0, resolving - chunk.count)
            save()
        }
        resolving = 0
        if let h = here { replan(from: h) }
    }

    func importFiles(_ urls: [URL]) async {
        var added = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let list = Takeout.listName(fromFileName: url.lastPathComponent)
            let ext = url.pathExtension.lowercased()
            let places: [Place]
            if ext == "csv" {
                places = Takeout.parseListCSV(String(decoding: data, as: UTF8.self), listName: list)
            } else {
                places = Takeout.parseSavedPlacesJSON(data, listName: list == "Saved Places" ? "Starred" : list)
            }
            for p in places { library.upsert(p) }
            added += places.count
        }
        save()
        let missing = library.unresolved.count
        importStatus = "Imported \(added) places" + (missing > 0 ? ", finding \(missing) on the map…" : ".")
        await resolvePending()
        let left = library.places.filter { $0.kind == .saved && !$0.isResolved }.count
        importStatus = "Imported \(added) places." + (left > 0 ? " \(left) could not be placed on the map." : "")
    }

    func addManual(name: String, at c: Coordinate?, note: String?) {
        library.upsert(Place(name: name, coordinate: c, kind: .saved, source: .manual, lists: ["Added in roam"], note: note))
        save()
        if let h = here { replan(from: h) }
    }

    func setMuted(_ id: String, _ muted: Bool) {
        guard var p = library.place(id: id) else { return }
        p.muted = muted
        update(p)
        if let h = here { replan(from: h) }
    }

    func delete(_ id: String) {
        library.remove(id: id)
        save()
        if let h = here { replan(from: h) }
    }

    // MARK: Audio guide

    func script(for p: Place) async throws -> String {
        if let s = library.place(id: p.id)?.guideScript, !s.isEmpty { return s }
        let service = GuideService(anthropicKey: settings.anthropicKey, model: settings.claudeModel, lang: settings.wikiLang)
        let text = try await service.script(for: p, city: city)
        if var q = library.place(id: p.id) {
            q.guideScript = text
            library.update(q)
            save()
        }
        return text
    }

    func listen(_ placeID: String) async {
        guard let p = library.place(id: placeID) else { return }
        if Narrator.shared.speakingPlaceID == placeID {
            Narrator.shared.togglePause()
            return
        }
        generating.insert(placeID)
        defer { generating.remove(placeID) }
        do {
            let text = try await script(for: p)
            Narrator.shared.speak(text, placeID: placeID, rate: settings.speechRate)
        } catch {
            toast = error.localizedDescription
        }
    }

    func isGenerating(_ id: String) -> Bool { generating.contains(id) }

    /// Night-time prep (on power and Wi-Fi): scripts for places within reach that do not have one yet.
    func prepareScripts(limit: Int = 25) async {
        guard settings.hasClaudeKey else { return }
        let centers = [here].compactMap { $0 } + trips.compactMap(\.center)
        guard !centers.isEmpty else { return }
        let todo = library.places.filter { p in
            guard p.guideScript == nil, !p.muted, let c = p.coordinate else { return false }
            return centers.contains { Geo.distance($0, c) < 30_000 }
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        for p in todo { _ = try? await script(for: p) }
    }

    // MARK: Notification actions

    func handleNotification(action: String, placeID: String) {
        switch action {
        case Notifier.listen:
            sheet = nil
            detailPlaceID = placeID
            autoplayPlaceID = placeID
        case Notifier.navigate:
            if let p = library.place(id: placeID), let c = p.coordinate {
                Navigator.walk(to: c, name: p.name, using: settings.navApp)
            }
        case Notifier.mute:
            setMuted(placeID, true)
        default:
            sheet = nil
            detailPlaceID = placeID
        }
    }

    // MARK: Trips

    func loadTrips() async {
        let events = await CalendarService.upcomingEvents()
        trips = TripPlanner.trips(from: events, home: settings.home ?? here)
    }

    var currentTrip: Trip? { TripPlanner.current(trips, now: Date(), here: here) }

    /// Reads a Google Doc, asks Claude for the places in it, and saves them (list "Doc: <title>").
    func extractPlaces(from file: DriveFile, trip: Trip?) async throws -> Int {
        guard settings.hasClaudeKey else { throw SourceError.missingKey("Anthropic key") }
        let text = try await GoogleAccount.shared.docText(file.id, clientID: settings.googleClientID)
        let reply = try Claude.parseText(await Net.data(Claude.request(
            model: settings.claudeModel, key: settings.anthropicKey, system: DocExtraction.system,
            user: DocExtraction.prompt(docTitle: file.name, text: text, destination: trip?.city), maxTokens: 4_000)))
        let found = DocExtraction.parse(reply)
        let service = NearbyService(googleKey: settings.googleMapsKey)
        var center = trip?.center
        if center == nil, let city = trip?.city { center = await Geocode.forward(city)?.0 }
        var count = 0
        for e in found {
            var p = Place(name: e.name, kind: .saved, source: .doc, lists: ["Doc: \(file.name)"], note: e.note,
                          url: file.link, scenic: e.type == "scenic")
            let query = Place(name: [e.name, e.city ?? trip?.city].compactMap { $0 }.joined(separator: ", "))
            let resolved = await service.resolve(query, near: center ?? here)
            p.coordinate = resolved.coordinate
            p.googlePlaceID = resolved.googlePlaceID
            p.address = resolved.address
            p.resolveAttempts = 3
            library.upsert(p)
            count += 1
        }
        save()
        if let h = here { replan(from: h) }
        return count
    }
}

/// Holds a background-task id so the expiration handler and the work can both end it exactly once.
final class TaskBox: @unchecked Sendable {
    var id: UIBackgroundTaskIdentifier = .invalid

    func end() {
        DispatchQueue.main.async {
            guard self.id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(self.id)
            self.id = .invalid
        }
    }
}
