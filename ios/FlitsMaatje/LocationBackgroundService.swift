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
    private var lastSpeedingSignature: String?
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
        AppLogger.log("LocationBackgroundService init")
    }

    func requestPermissionAndStart() {
        AppLogger.log("Locatie: permissie aanvragen")
        AlertNotifier.requestPermissions()
        applyAuthorizationState()
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else {
            statusText = "Locatieservices uitgeschakeld"
            AppLogger.error("Locatie: services uitgeschakeld op apparaat")
            return
        }
        AppLogger.log("Locatie: startUpdatingLocation (auth=\(manager.authorizationStatus.rawValue))")
        manager.startUpdatingLocation()
        isTracking = true
        statusText = "Achtergrond-tracking actief — flitsalarm + boete-indicatie"
        configureAudioSession()
    }

    func stop() {
        AppLogger.log("Locatie: stop")
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
        clearSpeedingState()
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
            applyAuthorizationState()
        }
    }

    private func applyAuthorizationState() {
        AppLogger.log("Locatie: autorisatie=\(manager.authorizationStatus.rawValue)")
        switch manager.authorizationStatus {
        case .authorizedAlways:
            enableBackgroundLocationIfNeeded(true)
            AppLogger.log("Locatie: achtergrond-updates ingeschakeld")
            statusText = "Altijd-toestemming — ideaal voor CarPlay op de achtergrond"
            startIfNeeded()
        case .authorizedWhenInUse:
            enableBackgroundLocationIfNeeded(false)
            statusText = "Alleen tijdens gebruik — zet op 'Altijd' voor achtergrondwaarschuwingen"
            startIfNeeded()
            manager.requestAlwaysAuthorization()
        case .denied, .restricted:
            statusText = "Geen locatietoestemming — ga naar Instellingen"
            AppLogger.error("Locatie: geweigerd of beperkt")
            stop()
        case .notDetermined:
            statusText = "Wacht op locatietoestemming…"
        @unknown default:
            break
        }
    }

    private func enableBackgroundLocationIfNeeded(_ enabled: Bool) {
        guard manager.allowsBackgroundLocationUpdates != enabled else { return }
        manager.allowsBackgroundLocationUpdates = enabled
        manager.showsBackgroundLocationIndicator = enabled
    }

    private func startIfNeeded() {
        guard !isTracking else { return }
        start()
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
            AppLogger.error("API nearby-alert mislukt: \(error.localizedDescription)")
            persistSnapshot(lat: lat, lng: lng, alert: currentAlert, message: statusText)
        }
    }

    private func updateCurrentSpeed(from location: CLLocation) {
        guard location.speed >= 0 else { return }
        currentSpeedKmh = Int((location.speed * 3.6).rounded())
        handleSpeedingFine()
    }

    private func shouldRunSpeedCheck(now: Date, location: CLLocation) -> Bool {
        let isSpeeding = isCurrentlySpeeding()
        let minInterval: TimeInterval = isSpeeding ? 2 : 4
        let minDistance: CLLocationDistance = isSpeeding ? 15 : 30

        guard now.timeIntervalSince(lastSpeedCheckAt) >= minInterval else { return false }
        guard let last = lastSpeedCheckLocation else { return true }
        return location.distance(from: last) >= minDistance
    }

    private func fetchSpeedCheck(lat: Double, lng: Double) async {
        let speed = currentSpeedKmh.map(Double.init)
        do {
            let response = try await FlitsMaatjeAPI.fetchSpeedCheck(lat: lat, lng: lng, speedKmh: speed)
            speedLimit = response.limit.maxspeed
            roadName = response.limit.road_name
            fineEstimate = response.fine

            if currentAlert == nil, let fineText = response.fine?.displayText(speedKmh: currentSpeedKmh, limit: speedLimit) {
                statusText = fineText
            }

            handleSpeedingFine()
        } catch {
            AppLogger.error("API speed-check mislukt: \(error.localizedDescription)")
            // Snelheidslimiet is optioneel — flitsalarm blijft werken
        }
    }

    private func isCurrentlySpeeding() -> Bool {
        if let speed = currentSpeedKmh, let limit = speedLimit, speed >= limit + 4 {
            return true
        }
        return (fineEstimate?.excess_kmh ?? 0) >= 4
    }

    private func handleSpeedingFine() {
        guard let fine = fineEstimate,
              let body = fine.displayText(speedKmh: currentSpeedKmh, limit: speedLimit) else {
            clearSpeedingState()
            return
        }

        let signature = "\(currentSpeedKmh ?? 0)-\(speedLimit ?? 0)-\(body)"
        guard signature != lastSpeedingSignature else { return }
        lastSpeedingSignature = signature

        AlertNotifier.updateSpeedingPopup(speedKmh: currentSpeedKmh, limit: speedLimit, fine: fine)
        CarPlayDrivingTaskCoordinator.shared.updateSpeeding(
            speedKmh: currentSpeedKmh,
            limit: speedLimit,
            fine: fine
        )

        if currentAlert == nil {
            statusText = body
        }
    }

    private func clearSpeedingState() {
        guard lastSpeedingSignature != nil else { return }
        lastSpeedingSignature = nil
        AlertNotifier.clearSpeedingPopup()
        CarPlayDrivingTaskCoordinator.shared.clearSpeeding()
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
