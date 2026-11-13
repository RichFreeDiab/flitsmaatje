import CoreLocation
import Foundation
import MapKit

/// Shared drive state for phone + CarPlay (feeds App Group + route corridor).
@MainActor
final class DriveSession: ObservableObject {
    static let shared = DriveSession()

    @Published private(set) var isActive = false
    @Published private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var course: CLLocationDirection = -1
    @Published var speedKmh: Int?
    @Published var currentAlert: NearbyAlert?
    @Published var laneItems: [LaneGuidanceItem] = []
    @Published private(set) var passedAlertIds: [String] = []
    @Published var layerTrapsEnabled = true
    @Published var layerIncidentsEnabled = true
    @Published var layerJamsEnabled = true

    private(set) var phoneOwnsServices = false

    private static let historyKey = "flitsmaatje.driveHistory"
    private static let sessionKey = "flitsmaatje.driveSession"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    var locationService: LocationBackgroundService { .shared }
    var navigationService: NavigationService { .shared }

    private init() {
        if let data = defaults.data(forKey: Self.historyKey),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            passedAlertIds = ids
        }
    }

    @discardableResult
    func ensureServices() -> (LocationBackgroundService, NavigationService) {
        isActive = true
        return (LocationBackgroundService.shared, NavigationService.shared)
    }

    func markPhoneOwned(_ owned: Bool) {
        phoneOwnsServices = owned
        isActive = owned || LocationBackgroundService.shared.isTracking
        persistLite()
    }

    func updateRoute(from route: MKRoute?) {
        guard let route else {
            routeCoordinates = []
            persistLite()
            return
        }
        var coordinates = Array(
            repeating: kCLLocationCoordinate2DInvalid,
            count: route.polyline.pointCount
        )
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: route.polyline.pointCount))
        routeCoordinates = Self.sample(coordinates.filter { CLLocationCoordinate2DIsValid($0) }, maxPoints: 90)
        persistLite()
    }

    func clearRoute() {
        routeCoordinates = []
        persistLite()
    }

    func notePassedAlert(_ alert: NearbyAlert) {
        guard !passedAlertIds.contains(alert.id) else { return }
        passedAlertIds.append(alert.id)
        if passedAlertIds.count > 40 {
            passedAlertIds = Array(passedAlertIds.suffix(40))
        }
        if let data = try? JSONEncoder().encode(passedAlertIds) {
            defaults.set(data, forKey: Self.historyKey)
        }
    }

    func syncFromLocation(_ location: LocationBackgroundService) {
        currentAlert = location.currentAlert
        speedKmh = location.currentSpeedKmh
        if let last = location.lastLocation, last.course >= 0 {
            course = last.course
        }
        persistLite()
    }

    func syncLanes(from sections: [LaneSection]) {
        laneItems = sections.first?.guidanceItems ?? []
    }

    var routeQueryValue: String? {
        guard routeCoordinates.count >= 2 else { return nil }
        return routeCoordinates
            .map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) }
            .joined(separator: ";")
    }

    private func persistLite() {
        let payload: [String: Any] = [
            "isActive": isActive,
            "speedKmh": speedKmh as Any,
            "course": course,
            "routeCount": routeCoordinates.count,
            "alertId": currentAlert?.id as Any,
        ]
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
