import AVFoundation
import CoreLocation
import Foundation
import UIKit

@MainActor
final class LocationBackgroundService: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// Manual singleton — `static let shared = …()` on @MainActor deadlocks on iOS 27
    /// (TestFlight 553/566 died between gps-before-service and gps-location-shared).
    private static var _shared: LocationBackgroundService?
    static var shared: LocationBackgroundService {
        if let existing = _shared { return existing }
        let created = LocationBackgroundService()
        _shared = created
        return created
    }

    @Published var isTracking = false
    @Published var statusText = "Wacht op locatietoestemming..."
    @Published var currentAlert: NearbyAlert?
    @Published var mapReports: [MapReport] = []
    @Published var currentSpeedKmh: Int?
    @Published var speedLimit: Int?
    @Published var speedZone: String?
    @Published var fineEstimate: FineEstimate?
    @Published var trafficInfo: TomTomTraffic?
    @Published var roadName: String?
    @Published var lastLocation: CLLocation?

    var speedingWarningText: String? {
        guard let speed = currentSpeedKmh, let limit = speedLimit else { return nil }
        let corrected = speed <= 100 ? speed - 3 : Int(Double(speed) * 0.97)
        let excess = corrected - limit
        return excess >= 4 ? "Te hard: +\(excess) km/u" : nil
    }

    var fineStatusText: String? {
        effectiveFineEstimate?.compactAmountText
    }

    var effectiveFineEstimate: FineEstimate? {
        guard let speed = currentSpeedKmh, let limit = speedLimit else { return nil }
        // Bereken bij iedere GPS-update direct lokaal. De server bepaalt nog
        // steeds de limiet en zone, maar een netwerkrequest blokkeert het bedrag niet.
        return FineCalculator.estimate(
            zone: speedZone,
            measuredKmh: speed,
            limitKmh: limit
        )
    }

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
        // Navigatie-apps krijgen zo vrijwel iedere GPS-update; 15 meter gaf
        // bij lage snelheid en optrekken een zichtbare achterstand.
        m.distanceFilter = kCLDistanceFilterNone
        m.pausesLocationUpdatesAutomatically = false
        m.activityType = .automotiveNavigation
        return m
    }()
    private var didConfigureManager = false
    private var locationProcessingTask: Task<Void, Never>?
    private var speedCheckTask: Task<Void, Never>?
    private var lastPollAt: Date = .distantPast
    private var lastEarlyPollAt: Date = .distantPast
    private var lastFullPollAt: Date = .distantPast
    private var cachedFixedAlert: NearbyAlert?
    private var lastSpeedCheckAt: Date = .distantPast
    private var lastSpeedCheckLocation: CLLocation?
    private var lastAlertId: String?
    private var passedDistanceThresholds: Set<Int> = []
    private var lastAlarmAt: Date = .distantPast
    private var lastSpeedingSignature: String?
    private var lastCarPlayRefreshAt: Date = .distantPast
    private var isAppActive = false
    private var recentSpeedSamples: [Int] = []
    private var lastAcceptedSpeedAt: Date = .distantPast
    private var previousLocation: CLLocation?
    private var speedCheckGeneration = 0
    private var lastSpeedLimitUpdatedAt: Date = .distantPast
    private var isSpeedCheckInFlight = false
    /// Pas na volledige startup: voorkomt crash door API/nav/audio tijdens boot.
    private var runtimeReady = false
    private static var startupInFlight = false

    /// Wordt door de telefoon- en CarPlay-navigatie gebruikt om elke GPS-update
    /// direct als routevoortgang te verwerken.
    var onLocationUpdate: ((CLLocation) -> Void)?
    private var locationUpdateHandlers: [UUID: (CLLocation) -> Void] = [:]

    /// Eén starter tegelijk (telefoon of CarPlay) — voorkomt dubbele activate-race.
    @discardableResult
    func beginExclusiveStartup() -> Bool {
        if isTracking || runtimeReady { return true }
        if Self.startupInFlight { return false }
        Self.startupInFlight = true
        return true
    }

    func markRuntimeReady() {
        runtimeReady = true
        Self.startupInFlight = false
        BootLogger.mark("location-runtime-ready")
        // Audio pas ná boot, niet tijdens startUpdatingLocation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.configureAudioSession()
        }
    }

    @discardableResult
    func addLocationUpdateHandler(_ handler: @escaping (CLLocation) -> Void) -> UUID {
        let id = UUID()
        locationUpdateHandlers[id] = handler
        return id
    }

    func removeLocationUpdateHandler(_ id: UUID?) {
        guard let id else { return }
        locationUpdateHandlers.removeValue(forKey: id)
    }

    private let distanceAlarmThresholds = [600, 400, 200, 100]
    private let alarmRepeatInterval: TimeInterval = 25
    private let carPlayRefreshInterval: TimeInterval = 0.5

    private override init() {
        super.init()
    }

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
        BootLogger.mark("location-activate-done")
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
        speedCheckTask?.cancel()
        locationProcessingTask = nil
        speedCheckTask = nil
        manager.stopUpdatingLocation()
        isTracking = false
        statusText = "Tracking gestopt"
        currentAlert = nil
        mapReports = []
        currentSpeedKmh = nil
        recentSpeedSamples.removeAll()
        lastAcceptedSpeedAt = .distantPast
        speedLimit = nil
        speedZone = nil
        fineEstimate = nil
        trafficInfo = nil
        roadName = nil
        lastLocation = nil
        previousLocation = nil
        speedCheckGeneration += 1
        lastSpeedLimitUpdatedAt = .distantPast
        isSpeedCheckInFlight = false
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
        locationProcessingTask = Task { [weak self] in
            guard let self else { return }
            await self.processLocation(location)
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

    /// Apple vereist: eerst startUpdatingLocation, dan pas allowsBackgroundLocationUpdates.
    private func startTracking(enableBackground: Bool) {
        BootLogger.mark("location-start-tracking")
        configureManagerIfNeeded()
        guard isAppActive else { return }
        guard manager.authorizationStatus == .authorizedAlways ||
              manager.authorizationStatus == .authorizedWhenInUse else {
            AppLogger.log("Locatie: nog geen toestemming")
            BootLogger.mark("location-start-no-auth")
            return
        }

        if !isTracking {
            AppLogger.log("Locatie: startUpdatingLocation (auth=\(manager.authorizationStatus.rawValue))")
            BootLogger.mark("location-before-start-updating")
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            manager.startUpdatingLocation()
            isTracking = true
            BootLogger.mark("location-after-start-updating")
            // Audio pas later — setActive tijdens boot crashte/killde op iOS 26/27.
        }

        // Achtergrond alleen op expliciet verzoek, nooit tijdens eerste boot.
        if enableBackground,
           runtimeReady,
           manager.authorizationStatus == .authorizedAlways,
           !manager.allowsBackgroundLocationUpdates {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            statusText = "Achtergrond-tracking actief - flitsalarm + boete-indicatie"
        } else if !enableBackground && manager.allowsBackgroundLocationUpdates {
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            statusText = "Tracking actief - flitsalarm + boete-indicatie"
        } else {
            statusText = "Tracking actief - flitsalarm + boete-indicatie"
        }
        BootLogger.mark("location-start-tracking-done")
    }

    private func startIfNeeded() {
        guard !isTracking else { return }
        let useBackground = manager.authorizationStatus == .authorizedAlways
        startTracking(enableBackground: useBackground)
    }

    private func processLocation(_ location: CLLocation) async {
        if Task.isCancelled { return }

        lastLocation = location
        updateCurrentSpeed(from: location)
        persistSnapshot(lat: location.coordinate.latitude, lng: location.coordinate.longitude, alert: currentAlert, message: statusText)

        // Tijdens boot geen nav/API/CarPlay-work — kill-window na gps-service-created.
        guard runtimeReady else {
            onLocationUpdate?(location)
            return
        }

        AppLogger.log("GPS update accuracy=\(Int(location.horizontalAccuracy))m speed=\(currentSpeedKmh ?? -1)kmh")
        if let nav = NavigationService.existing {
            nav.updateTrafficReports(mapReports)
            nav.updateProgress(location: location)
        }
        CarPlayNavigationCoordinator.existing?.updateNavigationProgress()
        onLocationUpdate?(location)
        for handler in locationUpdateHandlers.values {
            handler(location)
        }

        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        let now = Date()
        let speed = currentSpeedKmh

        if !isSpeedCheckInFlight, shouldRunSpeedCheck(now: now, location: location) {
            lastSpeedCheckAt = now
            lastSpeedCheckLocation = location
            speedCheckGeneration += 1
            let generation = speedCheckGeneration
            isSpeedCheckInFlight = true
            speedCheckTask = Task { @MainActor in
                await self.fetchSpeedCheckOffMain(
                    lat: lat,
                    lng: lng,
                    speedKmh: speed,
                    generation: generation
                )
            }
        }

        if Task.isCancelled { return }

        // Bewezen stabiele poll (pre-drive-context). Route meegeven mag; decode faalt soft.
        guard now.timeIntervalSince(lastPollAt) >= 2 else { return }
        lastPollAt = now
        let heading = location.course >= 0 ? location.course : nil
        let road = roadName
        let route = DriveSession.shared.routeQueryValue

        do {
            async let alertRequest = Task.detached(priority: .utility) {
                try await FlitsMaatjeAPI.fetchNearbyAlert(
                    lat: lat,
                    lng: lng,
                    heading: heading,
                    road: road,
                    route: route
                )
            }.value
            async let reportsRequest = Task.detached(priority: .utility) {
                try await FlitsMaatjeAPI.fetchReports(lat: lat, lng: lng)
            }.value
            let (alert, reports) = try await (alertRequest, reportsRequest)
            if Task.isCancelled { return }

            mapReports = reports
            applyAlert(alert, lat: lat, lng: lng, mapFallback: reports)
            DriveSession.shared.syncSnapshot(
                alertId: currentAlert?.id,
                speedKmh: currentSpeedKmh,
                course: lastLocation?.course ?? -1
            )
        } catch {
            if Task.isCancelled { return }
            statusText = "Kon API niet bereiken"
            AppLogger.error("API nearby-alert mislukt: \(error.localizedDescription)")
            persistSnapshot(lat: lat, lng: lng, alert: currentAlert, message: statusText)
        }
    }

    private func applyDriveContext(_ context: DriveContextResponse, lat: Double, lng: Double) {
        let traps = context.speed_traps + context.speed_traps_alt
        cachedFixedAlert = traps.first
        let reportAlerts = context.reports ?? (traps + context.incidents + context.traffic_jams)
        mapReports = reportAlerts.map { alert in
            MapReport(
                id: alert.id,
                type: alert.type,
                lat: alert.lat,
                lng: alert.lng,
                confirms: alert.confirms,
                distance_km: Double(alert.distance_m) / 1000.0,
                road: alert.road ?? alert.road_ref,
                hectometer: alert.hectometer
            )
        }
        applyAlert(context.alert, lat: lat, lng: lng, mapFallback: mapReports)
    }

    private func applyAlert(_ alert: NearbyAlert?, lat: Double, lng: Double, mapFallback: [MapReport]?) {
        if let mapFallback {
            mapReports = mapFallback
        }
        currentAlert = alert
        if let alert {
            var message = "\(alert.label) over \(alert.distance_m) m"
            if let road = alert.roadContextText {
                message += " - \(road)"
            }
            statusText = message
            persistSnapshot(lat: lat, lng: lng, alert: alert, message: statusText)
            handleFlitserAlarm(alert: alert)
            CarPlayNavigationCoordinator.existing?.handleFlitserAlert(alert)
            refreshCarPlay(alert: alert)
            if alert.distance_m <= 80 {
                DriveSession.shared.notePassedAlert(alert)
            }
        } else {
            statusText = effectiveFineEstimate?.displayText(speedKmh: currentSpeedKmh, limit: speedLimit) ?? "Geen meldingen in de buurt"
            persistSnapshot(lat: lat, lng: lng, alert: nil, message: statusText)
            resetAlarmState()
            CarPlayNavigationCoordinator.existing?.handleFlitserAlert(nil)
            refreshCarPlay(alert: nil)
        }
    }

    private func fetchSpeedCheckOffMain(
        lat: Double,
        lng: Double,
        speedKmh: Int?,
        generation: Int
    ) async {
        defer {
            if generation == speedCheckGeneration {
                isSpeedCheckInFlight = false
            }
        }
        let speed = speedKmh.map(Double.init)
        do {
            let response = try await Task.detached(priority: .utility) {
                try await FlitsMaatjeAPI.fetchSpeedCheck(lat: lat, lng: lng, speedKmh: speed)
            }.value
            guard !Task.isCancelled, generation == speedCheckGeneration else {
                AppLogger.log("Verouderde speed-check genegeerd")
                return
            }

            speedLimit = response.limit.maxspeed
            speedZone = response.limit.zone
            roadName = response.limit.road_name
            fineEstimate = response.fine
            trafficInfo = response.traffic
            lastSpeedLimitUpdatedAt = Date()

            if currentAlert == nil,
               let fineText = effectiveFineEstimate?.displayText(speedKmh: currentSpeedKmh, limit: speedLimit) {
                statusText = fineText
            }
            handleSpeedingFine()
            persistSnapshot(
                lat: lastLocation?.coordinate.latitude,
                lng: lastLocation?.coordinate.longitude,
                alert: currentAlert,
                message: statusText
            )
            // Boeteweergave ververs direct; deze update mag niet worden
            // overgeslagen door de flitser-refresh rate-limit.
            CarPlayDrivingTaskCoordinator.existing?.updateSpeeding(
                speedKmh: currentSpeedKmh,
                limit: speedLimit,
                fine: effectiveFineEstimate
            )
        } catch {
            if !Task.isCancelled {
                AppLogger.error("API speed-check mislukt: \(error.localizedDescription)")
            }
        }
    }

    private func updateCurrentSpeed(from location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 80 else {
            return
        }

        let coordinateSpeed = calculatedSpeed(from: location)
        let measuredSpeed: CLLocationSpeed
        if location.speed < 0 {
            measuredSpeed = coordinateSpeed
        } else if location.speed <= 0.5, coordinateSpeed >= 1.5 {
            // Sommige CarPlay/GPS-updates melden tijdelijk exact 0 terwijl
            // opeenvolgende coördinaten duidelijk verplaatsen.
            measuredSpeed = coordinateSpeed
        } else {
            measuredSpeed = location.speed
        }
        guard measuredSpeed >= 0 else { return }
        let candidate = Int((measuredSpeed * 3.6).rounded())
        guard candidate <= 220 else {
            AppLogger.error("GPS snelheid genegeerd: \(candidate) km/u")
            return
        }

        let now = Date()
        if let current = currentSpeedKmh,
           abs(candidate - current) > 50,
           now.timeIntervalSince(lastAcceptedSpeedAt) < 1.5 {
            AppLogger.error("GPS snelheidssprong genegeerd: \(current)→\(candidate) km/u")
            return
        }

        // Toon de actuele Core Location-snelheid direct; middelen veroorzaakte
        // merkbare vertraging bij optrekken en afremmen.
        currentSpeedKmh = candidate
        lastAcceptedSpeedAt = now
        handleSpeedingFine()
        previousLocation = location
    }

    private func calculatedSpeed(from location: CLLocation) -> CLLocationSpeed {
        guard let previousLocation else { return -1 }
        let seconds = location.timestamp.timeIntervalSince(previousLocation.timestamp)
        guard seconds >= 0.5, seconds <= 10 else { return -1 }
        return location.distance(from: previousLocation) / seconds
    }

    private func shouldRunSpeedCheck(now: Date, location: CLLocation) -> Bool {
        let isSpeeding = isCurrentlySpeeding()
        let minInterval: TimeInterval = isSpeeding ? 0.75 : 2.0
        let minDistance: CLLocationDistance = isSpeeding ? 5 : 15

        guard now.timeIntervalSince(lastSpeedCheckAt) >= minInterval else { return false }
        if speedLimit == nil || now.timeIntervalSince(lastSpeedLimitUpdatedAt) >= 5 {
            return true
        }
        guard let last = lastSpeedCheckLocation else { return true }
        return location.distance(from: last) >= minDistance
    }

    private func isCurrentlySpeeding() -> Bool {
        if let speed = currentSpeedKmh, let limit = speedLimit, speed >= limit + 4 {
            return true
        }
        return (effectiveFineEstimate?.excess_kmh ?? 0) >= 4
    }

    private func handleSpeedingFine() {
        let activeFine = effectiveFineEstimate
        guard let body = activeFine?.displayText(speedKmh: currentSpeedKmh, limit: speedLimit) ?? speedingWarningText else {
            clearSpeedingState()
            return
        }

        let signature = "\(currentSpeedKmh ?? 0)-\(speedLimit ?? 0)-\(body)"
        guard signature != lastSpeedingSignature else { return }
        lastSpeedingSignature = signature

        if let fine = activeFine {
            AlertNotifier.updateSpeedingPopup(speedKmh: currentSpeedKmh, limit: speedLimit, fine: fine)
        }
        refreshCarPlaySpeeding()
        CarPlayNavigationCoordinator.existing?.handleSpeedingFine(
            fine: activeFine,
            speedKmh: currentSpeedKmh,
            limit: speedLimit
        )

        if currentAlert == nil {
            statusText = body
        }
    }

    private func clearSpeedingState() {
        guard lastSpeedingSignature != nil else { return }
        lastSpeedingSignature = nil
        AlertNotifier.clearSpeedingPopup()
        refreshCarPlaySpeeding()
        CarPlayNavigationCoordinator.existing?.handleSpeedingFine(
            fine: nil,
            speedKmh: nil,
            limit: nil
        )
    }

    private func refreshCarPlay(alert: NearbyAlert?) {
        let now = Date()
        guard now.timeIntervalSince(lastCarPlayRefreshAt) >= carPlayRefreshInterval else { return }
        lastCarPlayRefreshAt = now
        CarPlayDrivingTaskCoordinator.existing?.update(alert: alert)
    }

    private func refreshCarPlaySpeeding() {
        let now = Date()
        guard now.timeIntervalSince(lastCarPlayRefreshAt) >= carPlayRefreshInterval else { return }
        lastCarPlayRefreshAt = now
        CarPlayDrivingTaskCoordinator.existing?.updateSpeeding(
            speedKmh: currentSpeedKmh,
            limit: speedLimit,
            fine: effectiveFineEstimate
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
        configureAudioSession()
        AlertNotifier.playFlitserAlarm()
        AlertNotifier.notifyFlitser(alert: alert)
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
            fineText: fineStatusText,
            statusMessage: message
        )
        SharedStore.save(snapshot)
    }

    private func configureAudioSession() {
        guard runtimeReady else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            AppLogger.error("Audio session mislukt: \(error.localizedDescription)")
            BootLogger.mark("audio-session-failed")
        }
    }
}
