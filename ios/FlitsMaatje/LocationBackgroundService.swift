import ActivityKit
import AudioToolbox
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

    private let manager = CLLocationManager()
    private var lastPollAt: Date = .distantPast
    private var lastAlertId: String?
    private var audioPlayer: AVAudioPlayer?
    private var liveActivity: Activity<FlitsMaatjeAttributes>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func requestPermissionAndStart() {
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
        statusText = "Achtergrond-tracking actief — widget en CarPlay worden bijgewerkt"
        configureAudioSession()
    }

    func stop() {
        manager.stopUpdatingLocation()
        isTracking = false
        statusText = "Tracking gestopt"
        currentAlert = nil
        endLiveActivity()
        persistSnapshot(lat: nil, lng: nil, alert: nil, message: "Tracking gestopt")
        WidgetCenter.shared.reloadTimelines(ofKind: "FlitsMaatjeWidget")
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
        let now = Date()
        guard now.timeIntervalSince(lastPollAt) >= 8 else { return }
        lastPollAt = now

        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude

        do {
            let alert = try await FlitsMaatjeAPI.fetchNearbyAlert(lat: lat, lng: lng)
            currentAlert = alert

            if let alert {
                statusText = "\(alert.label) over \(alert.distance_m) m"
                persistSnapshot(lat: lat, lng: lng, alert: alert, message: statusText)
                updateLiveActivity(alert: alert)
                if lastAlertId != alert.id {
                    playWarningSound()
                    lastAlertId = alert.id
                }
            } else {
                statusText = "Geen meldingen in de buurt"
                persistSnapshot(lat: lat, lng: lng, alert: nil, message: statusText)
                endLiveActivity()
                lastAlertId = nil
            }

            WidgetCenter.shared.reloadTimelines(ofKind: "FlitsMaatjeWidget")
        } catch {
            statusText = "Kon API niet bereiken"
            persistSnapshot(lat: lat, lng: lng, alert: currentAlert, message: statusText)
        }
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

    private func playWarningSound() {
        // Korte piep via systeemgeluid — werkt ook als andere apps audio afspelen (mixWithOthers)
        AudioServicesPlaySystemSound(1057)
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
            // Live Activity niet beschikbaar op dit device/iOS-versie — widget blijft werken
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
