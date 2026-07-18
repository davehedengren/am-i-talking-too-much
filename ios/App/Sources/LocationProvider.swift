import CoreLocation
import Foundation

/// One-shot location + reverse geocoding for labeling a saved event. Requests
/// when-in-use authorization the first time, takes a single fix, and turns it
/// into a friendly place name. Everything degrades gracefully: denied, timed
/// out, or offline all return empty fields so the save flow is never blocked —
/// the user can still type a title and save.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    struct Place {
        var name: String?
        var latitude: Double?
        var longitude: Double?
    }

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Resolve the current place. Returns empty `Place` fields when location is
    /// unavailable or not permitted. Bounded by a timeout so the save sheet's
    /// spinner can never hang on a slow fix or geocode.
    func currentPlace() async -> Place {
        await withTaskGroup(of: Place.self) { group in
            group.addTask { await self.resolvePlace() }
            group.addTask {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                return Place()
            }
            let first = await group.next() ?? Place()
            group.cancelAll()
            return first
        }
    }

    private func resolvePlace() async -> Place {
        let status = await ensureAuthorized()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return Place()
        }
        guard let coordinate = await requestOneShot(),
              CLLocationCoordinate2DIsValid(coordinate) else {
            return Place()
        }
        let name = await reverseGeocode(coordinate)
        return Place(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func ensureAuthorized() async -> CLAuthorizationStatus {
        let current = manager.authorizationStatus
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private func requestOneShot() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks?.first else { return nil }
        // Prefer a venue/POI name, then the neighborhood or city.
        return placemark.name ?? placemark.subLocality ?? placemark.locality ?? placemark.administrativeArea
    }

    // MARK: - CLLocationManagerDelegate
    // Delivered on the main run loop (the manager was created on the main
    // actor); values are copied out before hopping so nothing non-Sendable
    // crosses the boundary.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // Ignore the transient .notDetermined callback delivered the moment the
        // delegate is set — resuming on it would abandon the request before the
        // user answers the permission prompt. Wait for the real decision.
        guard status != .notDetermined else { return }
        Task { @MainActor in
            guard let continuation = authContinuation else { return }
            authContinuation = nil
            continuation.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil
            continuation.resume(returning: coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil
            continuation.resume(returning: nil)
        }
    }
}
