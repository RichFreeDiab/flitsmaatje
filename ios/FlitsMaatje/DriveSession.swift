import CoreLocation
import Foundation
import MapKit

/// Thread-safe route/corridor state for phone + CarPlay.
/// Not an ObservableObject and not @MainActor — avoids MainActor `static let`
/// initialization deadlocks that killed TestFlight builds 553/566 at GPS start.
final class DriveSession: @unchecked Sendable {
    static var shared: DriveSession {
        if let existing = _shared { return existing }
        lock.lock()
        defer { lock.unlock() }
        if let existing = _shared { return existing }
        let created = DriveSession()
        _shared = created
        return created
    }

    private static var _shared: DriveSession?
    private static let lock = NSLock()

    private let stateLock = NSLock()
    private var routePoints: [[Double]] = []
    private var passedAlertIds: [String] = []
    private var phoneOwnsServices = false
    private var isActive = false
    private var speedKmh: Int?
    private var course: CLLocationDirection = -1
    private var currentAlertId: String?

    private static let historyKey = "flitsmaatje.driveHistory"
    private static let sessionKey = "flitsmaatje.driveSession"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    private init() {
        if let data = defaults.data(forKey: Self.historyKey),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            passedAlertIds = ids
        }
    }

    func markPhoneOwned(_ owned: Bool) {
        stateLock.lock()
        phoneOwnsServices = owned
        isActive = owned
        stateLock.unlock()
        persistLite()
    }

    func updateRoute(from route: MKRoute?) {
        guard let route else {
            stateLock.lock()
            routePoints = []
            stateLock.unlock()
            persistLite()
            return
        }
        var coordinates = Array(
            repeating: kCLLocationCoordinate2DInvalid,
            count: route.polyline.pointCount
        )
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: route.polyline.pointCount))
        let sampled = Self.sample(coordinates.filter { CLLocationCoordinate2DIsValid($0) }, maxPoints: 90)
        stateLock.lock()
        routePoints = sampled.map { [$0.latitude, $0.longitude] }
        stateLock.unlock()
        persistLite()
    }

    func clearRoute() {
        stateLock.lock()
        routePoints = []
        stateLock.unlock()
        persistLite()
    }

    func notePassedAlert(_ alert: NearbyAlert) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !passedAlertIds.contains(alert.id) else { return }
        passedAlertIds.append(alert.id)
        if passedAlertIds.count > 40 {
            passedAlertIds = Array(passedAlertIds.suffix(40))
        }
        let snapshot = passedAlertIds
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.historyKey)
        }
    }

    func syncSnapshot(alertId: String?, speedKmh: Int?, course: CLLocationDirection) {
        stateLock.lock()
        currentAlertId = alertId
        self.speedKmh = speedKmh
        if course >= 0 {
            self.course = course
        }
        stateLock.unlock()
        persistLite()
    }

    func syncLanes(from sections: [LaneSection]) {
        // Lane strip is owned by NavigationService; keep API for call-site stability.
        _ = sections
    }

    var routeQueryValue: String? {
        stateLock.lock()
        let points = routePoints
        stateLock.unlock()
        guard points.count >= 2 else { return nil }
        return points
            .compactMap { pair -> String? in
                guard pair.count >= 2 else { return nil }
                return String(format: "%.5f,%.5f", pair[0], pair[1])
            }
            .joined(separator: ";")
    }

    private func persistLite() {
        stateLock.lock()
        var payload: [String: Any] = [
            "isActive": isActive,
            "course": course,
            "routeCount": routePoints.count,
            "phoneOwns": phoneOwnsServices,
        ]
        if let speedKmh {
            payload["speedKmh"] = speedKmh
        }
        if let currentAlertId {
            payload["alertId"] = currentAlertId
        }
        stateLock.unlock()
        // NSNull in a dict crashes UserDefaults (NSInvalidArgumentException on 599/617).
        defaults.set(payload, forKey: Self.sessionKey)
    }

    private static func sample(_ coords: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard coords.count > maxPoints, maxPoints > 2 else { return coords }
        let step = max(1, coords.count / maxPoints)
        var sampled = stride(from: 0, to: coords.count, by: step).map { coords[$0] }
        if let last = coords.last,
           sampled.last.map({ $0.latitude != last.latitude || $0.longitude != last.longitude }) ?? true {
            sampled.append(last)
        }
        return sampled
    }
}
