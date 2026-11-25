import CoreLocation
import UIKit

/// Battery-first location: no continuous GPS, ever.
/// - Significant-change updates (cell and Wi-Fi, roughly every 500 m) wake the app, even after it was killed.
/// - Up to 19 place geofences plus one "you moved" boundary; iOS watches them in hardware.
/// - The buttons ask for one fix and stop.
final class LocationEngine: NSObject, CLLocationManagerDelegate {
    static let shared = LocationEngine()

    private let manager = CLLocationManager()
    private var oneShot: [CheckedContinuation<CLLocation, Error>] = []

    /// Called on the main queue when the app should re-plan (significant change, left the boundary).
    var onMove: ((CLLocation) -> Void)?
    /// Called on the main queue with a place id when a geofence is entered.
    var onEnter: ((String) -> Void)?
    var onAuthChange: ((CLAuthorizationStatus) -> Void)?

    private(set) var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
        lastLocation = manager.location
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }
    var hasAlways: Bool { manager.authorizationStatus == .authorizedAlways }

    /// Call at launch (including background relaunches) so pending region and significant-change events are delivered.
    func start() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        if hasAlways {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    /// iOS only shows the Always prompt after When In Use was granted.
    func requestAlways() { manager.requestAlwaysAuthorization() }

    /// One accurate fix for the buttons, then the radio goes quiet again.
    func currentLocation(maxAge: TimeInterval = 60) async throws -> CLLocation {
        if let l = manager.location, -l.timestamp.timeIntervalSinceNow < maxAge, l.horizontalAccuracy >= 0, l.horizontalAccuracy < 150 {
            lastLocation = l
            return l
        }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.main.async {
                self.oneShot.append(cont)
                self.manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                self.manager.requestLocation()
            }
        }
    }

    /// Replaces the monitored regions with the plan's.
    func apply(_ plan: GeofencePlan) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self), hasAlways else { return }
        let maxR = manager.maximumRegionMonitoringDistance
        let wanted = Set(plan.regions.map(\.id) + [plan.refresh.id])
        for r in manager.monitoredRegions where r.identifier.hasPrefix("roam.") {
            // Re-add the refresh boundary every time: its center moves with you.
            if !wanted.contains(r.identifier) || r.identifier == plan.refresh.id {
                manager.stopMonitoring(for: r)
            }
        }
        let existing = Set(manager.monitoredRegions.map(\.identifier))
        for g in plan.regions where !existing.contains(g.id) {
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: g.center.lat, longitude: g.center.lng),
                                          radius: min(g.radius, maxR), identifier: g.id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
        let refresh = CLCircularRegion(center: CLLocationCoordinate2D(latitude: plan.refresh.center.lat, longitude: plan.refresh.center.lng),
                                       radius: min(plan.refresh.radius, maxR), identifier: plan.refresh.id)
        refresh.notifyOnEntry = false
        refresh.notifyOnExit = true
        manager.startMonitoring(for: refresh)
    }

    func stopAll() {
        manager.stopMonitoringSignificantLocationChanges()
        for r in manager.monitoredRegions where r.identifier.hasPrefix("roam.") { manager.stopMonitoring(for: r) }
    }

    var monitoredCount: Int { manager.monitoredRegions.filter { $0.identifier.hasPrefix("roam.") }.count }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastLocation = loc
        if !oneShot.isEmpty {
            let waiting = oneShot
            oneShot.removeAll()
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            waiting.forEach { $0.resume(returning: loc) }
            return
        }
        // Significant-change delivery.
        onMove?(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !oneShot.isEmpty else { return }
        if let l = manager.location {
            let waiting = oneShot
            oneShot.removeAll()
            waiting.forEach { $0.resume(returning: l) }
            return
        }
        let waiting = oneShot
        oneShot.removeAll()
        waiting.forEach { $0.resume(throwing: error) }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let id = GeofencePlanner.placeID(from: region.identifier) else { return }
        onEnter?(id)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == GeofencePlanner.refreshID else { return }
        if let l = manager.location { lastLocation = l; onMove?(l) }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // Usually the 20-region limit after an OS-level change; the next re-plan fixes it.
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways { manager.startMonitoringSignificantLocationChanges() }
        onAuthChange?(manager.authorizationStatus)
    }
}

extension CLLocation {
    var coord: Coordinate { Coordinate(lat: coordinate.latitude, lng: coordinate.longitude) }
}

extension Coordinate {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}
