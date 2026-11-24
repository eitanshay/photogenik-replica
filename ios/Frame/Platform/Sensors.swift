import CoreLocation
import CoreMotion
import Foundation

/// Motion (gravity and attitude, 20 Hz) and location (for the sun). Callbacks arrive on the main queue.
final class Sensors: NSObject, CLLocationManagerDelegate {
    struct MotionSample {
        var gravity: (x: Double, y: Double, z: Double)
        var matrix: [[Double]]
        var northReferenced: Bool
    }

    private let motion = CMMotionManager()
    private let locationManager = CLLocationManager()
    private var referenceIsNorth = false
    /// True north minus magnetic north, from the compass. Added to magnetic headings.
    private(set) var declination: Double = 0

    var onMotion: ((MotionSample) -> Void)?
    var onLocation: ((CLLocation) -> Void)?
    private(set) var location: CLLocation?

    func start() {
        if motion.isDeviceMotionAvailable && !motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 1.0 / 20
            // Magnetic north needs no location permission; the compass heading supplies the declination.
            let frames = CMMotionManager.availableAttitudeReferenceFrames()
            let ref: CMAttitudeReferenceFrame = frames.contains(.xMagneticNorthZVertical) ? .xMagneticNorthZVertical : .xArbitraryCorrectedZVertical
            referenceIsNorth = ref == .xMagneticNorthZVertical
            motion.startDeviceMotionUpdates(using: ref, to: .main) { [weak self] dm, _ in
                guard let self, let dm else { return }
                let r = dm.attitude.rotationMatrix
                let m = [[r.m11, r.m12, r.m13], [r.m21, r.m22, r.m23], [r.m31, r.m32, r.m33]]
                self.onMotion?(MotionSample(gravity: (dm.gravity.x, dm.gravity.y, dm.gravity.z), matrix: m,
                                            northReferenced: self.referenceIsNorth))
            }
        }
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 200
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startLocation()
        default:
            break
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    private func startLocation() {
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.headingFilter = 5
            locationManager.startUpdatingHeading()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: startLocation()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        location = last
        onLocation?(last)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.trueHeading >= 0, newHeading.headingAccuracy >= 0 else { return }
        declination = MathX.wrap180(newHeading.trueHeading - newHeading.magneticHeading)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
