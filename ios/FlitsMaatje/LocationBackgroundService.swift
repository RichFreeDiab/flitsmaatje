import ActivityKit
import AVFoundation
import CoreLocation
import Foundation
import UIKit
import WidgetKit

@MainActor
final class LocationBackgroundService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isTracking = false
    @Published var statusText = "Wacht op locatietoestemming…"
    @Published var currentAlert: NearbyAlert?
    @Published var currentSpeedKmh: Int?
    @Published var speedLimit: Int?
    @Published var fineEstimate: FineEstimate?
    @Published var roadName: String?
    @Published var lastLocation: CLLocation?

    private let manager = CLLocationManager()
    private var lastPollAt: Date = .distantPast
    private var lastSpeedCheckAt: Date = .distantPast
    private var lastSpeedCheckLocation: CLLocation?
    private var lastAlertId: String?
    private var passedDistanceThresholds: Set<Int> = []
    private var lastAlarmAt: Date = .distantPast
    private var liveActivity: Activity<FlitsMaatjeAttributes>?

    private let distanceAlarmThresholds = [600, 400, 200, 100]
    private let alarmRepeatInterval: TimeInterval = 25

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 15
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func requestPermissionAndStart() {
        AlertNotifier.requestPermissions()
        manager.requestWhenInUseAuthorization()
        manager.requestAlwaysAuthorization()
        start()
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else {
            statusText = "Locatieservices uitgeschakeld"
            return
        }
        manager.startUpdatingLocation()
        isTracking = true
        statusText = "Achtergrond-tracking actief — flitsalarm + boete-indicatie"
        configureAudioSession()
    }

    func stop() {
        manager.stopUpdatingLocation()
        isTracking = false
        statusText = "Tracking gestopt"
        currentAlert = nil
        currentSpeedKmh = nil
        speedLimit = nil
        fineEstimate = nil
        roadName = nil
        lastLocation = nil
        resetAlarmState()
        endLiveActivity()
        persistSnapshot(lat: nil, lng: nil, alert: nil, message: "Tracking gestopt")
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await handleLocation(location)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways:
                statusText = "Altijd-toestemming — ideaal voor CarPlay op de achtergrond"
            case .authorizedWhenInUse:
                statusText = "Alleen tijdens gebruik — zet op 'Altijd' voor achtergrondwaarschuwingen"
            case .denied, .restricted:
                statusText = "Geen locatietoestemming — ga naar Instellingen"
                isTracking = false
            default:
                break
            }
        }
    }

    private func handleLocation(_ location: CLLocation) async {
        lastLocation = location
        updateCurrentSpeed(from: location)

        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        let now = Date()

        if shouldRunSpeedCheck(now: now, location: location) {
            lastSpeedCheckAt = now
            lastSpeedCheckLocation = location
            await fetchSpeedCheck(lat: lat, lng: lng)
        }

        guard now.timeIntervalSince(lastPollAt) >= 8 else { return }
        lastPollAt = now

        do {
            let alert = try await FlitsMaatjeAPI.fetchNearbyAlert(lat: lat, lng: lng)
            currentAlert = alert

            if let alert {
                statusText = "\(alert.label) over \(alert.distance_m) m"
                persistSnapshot(lat: lat, lng: lng, alert: alert, message: statusText)
                updateLiveActivity(alert: alert)
                handleFlitserAlarm(alert: alert)
            } else {
                statusText = fineEstimate?.displayText ?? "Geen meldingen in de buurt"
                persistSnapshot(lat: lat, lng: lng, alert: nil, message: statusText)
                endLiveActivity()
                resetAlarmState()
            }

            WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
        } catch {
            statusText = "Kon API niet bereiken"
            persistSnapshot(lat: lat, lng: lng, alert: currentAlert, message: statusText)
        }
    }

    private func updateCurrentSpeed(from location: CLLocation) {
        guard location.speed >= 0 else { return }
        currentSpeedKmh = Int((location.speed * 3.6).rounded())
    }

    private func shouldRunSpeedCheck(now: Date, location: CLLocation) -> Bool {
        guard now.timeIntervalSince(lastSpeedCheckAt) >= 4 else { return false }
        guard let last = lastSpeedCheckLocation else { return true }
        return location.distance(from: last) >= 30
    }

    private func fetchSpeedCheck(lat: Double, lng: Double) async {
        let speed = currentSpeedKmh.map(Double.init)
        do {
            let response = try await FlitsMaatjeAPI.fetchSpeedCheck(lat: lat, lng: lng, speedKmh: speed)
            speedLimit = response.limit.maxspeed
            roadName = response.limit.road_name
            fineEstimate = response.fine

            if currentAlert == nil, let fineText = response.fine?.displayText {
                statusText = fineText
            }
        } catch {
            // Snelheidslimiet is optioneel — flitsalarm blijft werken
        }
    }

    private func handleFlitserAlarm(alert: NearbyAlert) {
        var shouldAlarm = false

        if lastAlertId != alert.id {
            passedDistanceThresholds = []
            lastAlertId = alert.id
            shouldAlarm = true
        } else {
            for threshold in distanceAlarmThresholds {
                if alert.distance_m <= threshold, !passedDistanceThresholds.contains(threshold) {
                    passedDistanceThresholds.insert(threshold)
                    shouldAlarm = true
                    break
                }
            }
            if !shouldAlarm, Date().timeIntervalSince(lastAlarmAt) >= alarmRepeatInterval {
                shouldAlarm = true
            }
        }

        guard shouldAlarm else { return }

        lastAlarmAt = Date()
        AlertNotifier.playFlitserAlarm()
        AlertNotifier.notifyFlitser(alert: alert)
        AlertNotifier.speakFlitser(alert: alert)
    }

    private func resetAlarmState() {
        lastAlertId = nil
        passedDistanceThresholds = []
        lastAlarmAt = .distantPast
    }

    private func persistSnapshot(lat: Double?, lng: Double?, alert: NearbyAlert?, message: String) {
        let snapshot = WidgetSnapshot(
            updatedAt: Date(),
            latitude: lat,
            longitude: lng,
            alert: alert,
            statusMessage: message
        )
        SharedStore.save(snapshot)
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Live Activity

    private func updateLiveActivity(alert: NearbyAlert) {
        let state = FlitsMaatjeAttributes.ContentState(
            reportType: alert.type,
            label: alert.label,
            distanceMeters: alert.distance_m,
            icon: alert.icon
        )

        if let liveActivity {
            Task { await liveActivity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))) }
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = FlitsMaatjeAttributes(startedAt: Date())
        do {
            liveActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)),
                pushType: nil
            )
        } catch {
            // Live Activity niet beschikbaar — widget blijft werken
        }
    }

    private func endLiveActivity() {
        guard let liveActivity else { return }
        Task {
            await liveActivity.end(nil, dismissalPolicy: .immediate)
        }
        self.liveActivity = nil
    }
}
