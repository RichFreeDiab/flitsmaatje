import AVFoundation
import CoreLocation
import Foundation
import UIKit

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

    var managerAuthorizationIsAlways: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    var managerAuthorizationIsWhenInUse: Bool {
        manager.authorizationStatus == .authorizedWhenInUse
    }

    private lazy var manager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        m.distanceFilter = 15
        m.pausesLocationUpdatesAutomatically = false
        m.activityType = .automotiveNavigation
        return m
    }()
    private var didConfigureManager = false
    private var locationProcessingTask: Task<Void, Never>?
    private var lastPollAt: Date = .distantPast
    private var lastSpeedCheckAt: Date = .distantPast
    private var lastSpeedCheckLocation: CLLocation?
    private var lastAlertId: String?
    private var passedDistanceThresholds: Set<Int> = []
    private var lastAlarmAt: Date = .distantPast
    private var lastSpeedingSignature: String?
    private var lastCarPlayRefreshAt: Date = .distantPast
    private var isAppActive = false

    /// Wordt door de telefoon- en CarPlay-navigatie gebruikt om elke GPS-update\n    /// direct als routevoortgang te verwerken.\n    var onLocationUpdate: ((CLLocation) -> Void)?\n
    private let distanceAlarmThresholds = [600, 400, 200, 100]
    private let alarmRepeatInterval: TimeInterval = 25
    private let carPlayRefreshInterval: TimeInterval = 2

    func prepareForUse() {
        BootLogger.mark("location-prepare")
        configureManagerIfNeeded()
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Alleen voorgrond-GPS — geen achtergrondvlag (crash op iOS 26).
    func activateForegroundOnly() {
        isAppActive = true
        BootLogger.mark("location-activate-foreground")
        applyAuthorizationState(allowBackground: false)
    }

    func requestPermissionAndStart() {
        prepareForUse()
        DispatchQueue.main.async {
            AlertNotifier.requestPermissions()
        }
    }

    func activateWhenReady() {
        isAppActive = true
        AppLogger.markBootStage("location-activate")
        applyAuthorizationState(allowBackground: manager.authorizationStatus == .authorizedAlways)
    }

    func requestAlwaysPermission() {
        guard manager.authorizationStatus == .authorizedWhenInUse else {
            enableBackgroundTrackingIfAuthorized()
            return
        }
        AppLogger.log("Locatie: Altijd-toestemming aanvragen")
        manager.requestAlwaysAuthorization()
    }

    func start() {
        guard isAppActive else {
            AppLogger.log("Locatie: start uitgesteld tot app actief is")
            return
        }
        startTracking(enableBackground: false)
    }

    func enableBackgroundTrackingIfAuthorized() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        startTracking(enableBackground: true)
    }

    func stop() {
        AppLogger.log("Locatie: stop")
        locationProcessingTask?.cancel()
        locationProcessingTask = nil
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
        persistSnapshot(lat: nil, lng: nil, alert: nil, message: "Tracking gestopt")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.scheduleLocationProcessing(location)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.applyAuthorizationState(allowBackground: false)
        }
    }

    private func configureManagerIfNeeded() {
        guard !didConfigureManager else { return }
        didConfigureManager = true
        AppLogger.log("LocationBackgroundService configure")
        _ = manager
    }

    private func scheduleLocationProcessing(_ location: CLLocation) {
        locationProcessingTask?.cancel()
        locationProcessingTask = Task {
            await processLocation(location)
        }
    }

    private func applyAuthorizationState(allowBackground: Bool) {
        AppLogger.log("Locatie: autorisatie=\(manager.authorizationStatus.rawValue)")
        switch manager.authorizationStatus {
        case .authorizedAlways:
            statusText = allowBackground
                ? "Altijd-toestemming — achtergrond actief"
                : "Altijd-toestemming — tik voor achtergrond/CarPlay"
            if isAppActive {
                startTracking(enableBackground: allowBackground)
            }
        case .authorizedWhenInUse:
            statusText = "Tracking actief tijdens gebruik"
            if isAppActive {
                startTracking(enableBackground: false)
            }
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

    /// Apple vereist: eerst startUpdatingLocation, dán pas allowsBackgroundLocationUpdates.
    private func startTracking(enableBackground: Bool) {
        configureManagerIfNeeded()
        guard isAppActive else { return }
        guard manager.authorizationStatus == .authorizedAlways ||
              manager.authorizationStatus == .authorizedWhenInUse else {
            AppLogger.log("Locatie: nog geen toestemming")
            return
        }

        if !isTracking {
            AppLogger.log("Locatie: startUpdatingLocation (auth=\(manager.authorizationStatus.rawValue))")
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            manager.startUpdatingLocation()
            isTracking = true
            configureAudioSession()
        }

        let wantsBackground = enableBackground && manager.authorizationStatus == .authorizedAlways
        if wantsBackground && !manager.allowsBackgroundLocationUpdates {
            // Extra vertraging: achtergrond pas na stabiele voorgrond-GPS
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.isTracking, self.manager.authorizationStatus == .authorizedAlways else { return }
                self.manager.allowsBackgroundLocationUpdates = true
                self.manager.showsBackgroundLocationIndicator = true
                AppLogger.log("Locatie: achtergrond-updates=aan")
                self.statusText = "Achtergrond-tracking actief"
            }
        } else if !wantsBackground && manager.allowsBackgroundLocationUpdates {
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            AppLogger.log("Locatie: achtergrond-updates=uit")
        }

        statusText = wantsBackground
            ? "Achtergrond-tracking actief — flitsalarm + boete-indicatie"
            : "Tracking actief — flitsalarm + boete-indicatie"
    }

    private func startIfNeeded() {
        guard !isTracking else { return }
        let useBackground = manager.authorizationStatus == .authorizedAlways
        startTracking(enableBackground: useBackground)
    }

    private func processLocation(_ location: CLLocation) async {
        if Task.isCancelled { return }

        lastLocation = location
        AppLogger.log("GPS update accuracy=\\(Int(location.horizontalAccuracy))m speed=\\(currentSpeedKmh ?? -1)kmh")
        updateCurrentSpeed(from: location)

        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        let now = Date()
        let speed = currentSpeedKmh

        if shouldRunSpeedCheck(now: now, location: location) {
            lastSpeedCheckAt = now
            lastSpeedCheckLocation = location
            await fetchSpeedCheckOffMain(lat: lat, lng: lng, speedKmh: speed)
        }

        if Task.isCancelled { return }
        guard now.timeIntervalSince(lastPollAt) >= 8 else { return }
        lastPollAt = now

        do {
            let alert = try await Task.detached(priority: .utility) {
                try await FlitsMaatjeAPI.fetchNearbyAlert(lat: lat, lng: lng)
            }.value
            if Task.isCancelled { return }

            currentAlert = alert
            if let alert {
                statusText = "\(alert.label) over \(alert.distance_m) m"
                persistSnapshot(lat: lat, lng: lng, alert: alert, message: statusText)
                handleFlitserAlarm(alert: alert)
                CarPlayNavigationCoordinator.shared.handleFlitserAlert(alert)
                refreshCarPlay(alert: alert)
            } else {
                statusText = fineEstimate?.displayText(speedKmh: currentSpeedKmh, limit: speedLimit) ?? "Geen meldingen in de buurt"
                persistSnapshot(lat: lat, lng: lng, alert: nil, message: statusText)
                resetAlarmState()
                CarPlayNavigationCoordinator.shared.handleFlitserAlert(nil)
                refreshCarPlay(alert: nil)
            }
        } catch {
            if Task.isCancelled { return }
            statusText = "Kon API niet bereiken"
            AppLogger.error("API nearby-alert mislukt: \(error.localizedDescription)")
            persistSnapshot(lat: lat, lng: lng, alert: currentAlert, message: statusText)
        }
    }

    private func fetchSpeedCheckOffMain(lat: Double, lng: Double, speedKmh: Int?) async {
        let speed = speedKmh.map(Double.init)
        do {
            let response = try await Task.detached(priority: .utility) {
                try await FlitsMaatjeAPI.fetchSpeedCheck(lat: lat, lng: lng, speedKmh: speed)
            }.value
            if Task.isCancelled { return }

            speedLimit = response.limit.maxspeed
            roadName = response.limit.road_name
            fineEstimate = response.fine

            if currentAlert == nil,
               let fineText = response.fine?.displayText(speedKmh: currentSpeedKmh, limit: speedLimit) {
                statusText = fineText
            }
            handleSpeedingFine()
        } catch {
            if !Task.isCancelled {
                AppLogger.error("API speed-check mislukt: \(error.localizedDescription)")
            }
        }
    }

    private func updateCurrentSpeed(from location: CLLocation) {
        guard location.speed >= 0 else { return }
        currentSpeedKmh = Int((location.speed * 3.6).rounded())
        handleSpeedingFine()
    }

    private func shouldRunSpeedCheck(now: Date, location: CLLocation) -> Bool {
        let isSpeeding = isCurrentlySpeeding()
        let minInterval: TimeInterval = isSpeeding ? 3 : 5
        let minDistance: CLLocationDistance = isSpeeding ? 20 : 40

        guard now.timeIntervalSince(lastSpeedCheckAt) >= minInterval else { return false }
        guard let last = lastSpeedCheckLocation else { return true }
        return location.distance(from: last) >= minDistance
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
        refreshCarPlaySpeeding()

        if currentAlert == nil {
            statusText = body
        }
    }

    private func clearSpeedingState() {
        guard lastSpeedingSignature != nil else { return }
        lastSpeedingSignature = nil
        AlertNotifier.clearSpeedingPopup()
        refreshCarPlaySpeeding()
    }

    private func refreshCarPlay(alert: NearbyAlert?) {
        let now = Date()
        guard now.timeIntervalSince(lastCarPlayRefreshAt) >= carPlayRefreshInterval else { return }
        lastCarPlayRefreshAt = now
        CarPlayDrivingTaskCoordinator.shared.update(alert: alert)
    }

    private func refreshCarPlaySpeeding() {
        let now = Date()
        guard now.timeIntervalSince(lastCarPlayRefreshAt) >= carPlayRefreshInterval else { return }
        lastCarPlayRefreshAt = now
        CarPlayDrivingTaskCoordinator.shared.updateSpeeding(
            speedKmh: currentSpeedKmh,
            limit: speedLimit,
            fine: fineEstimate
        )
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
            speedKmh: currentSpeedKmh,
            speedLimitKmh: speedLimit,
            fineText: fineEstimate?.displayText(speedKmh: currentSpeedKmh, limit: speedLimit),
            statusMessage: message
        )
        SharedStore.save(snapshot)
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
