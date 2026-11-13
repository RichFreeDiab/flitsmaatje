import AudioToolbox
import AVFoundation
import Foundation
import UIKit
import UserNotifications

/// Geluid, trilling, CarPlay-notificatie en gesproken waarschuwing bij flitsers in de buurt.
enum AlertNotifier {
    // Korte systeemtoon blijft actief; gesproken tekst staat standaard uit.
    static var speechEnabled = false
    private static let flitserCategoryId = "flitser.carplay"
    private static let speedingCategoryId = "speeding.carplay"
    private static let speedingNotificationId = "flitsmaatje.speeding.live"
    private static var lastFlitserNotificationAt: Date = .distantPast
    private static var lastSpokenAt: Date = .distantPast
    private static let synthesizer = AVSpeechSynthesizer()

    static func requestPermissions() {
        registerCategories()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .carPlay]) { _, _ in }
    }

    static func playFlitserAlarm() {
        AudioServicesPlaySystemSound(1057)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            AudioServicesPlaySystemSound(1057)
        }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    /// Toont een banner op CarPlay (iOS 18.4+) ook als Flitsmeister op het hoofdscherm staat.
    static func notifyFlitser(alert: NearbyAlert) {
        speakFlitser(alert: alert)
        let now = Date()
        guard now.timeIntervalSince(lastFlitserNotificationAt) >= 20 else { return }
        lastFlitserNotificationAt = now

        guard !CarPlaySessionTracker.isForegroundOnCarPlay else { return }

        let content = UNMutableNotificationContent()
        content.title = alert.label
        content.subtitle = Self.distanceCopy(for: alert)
        content.body = "\(alert.icon) FlitsMaatje"
        content.sound = .default
        content.categoryIdentifier = flitserCategoryId
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let request = UNNotificationRequest(
            identifier: "flits-\(alert.id)-\(Int(now.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Stille, realtime CarPlay-popup bij te hard rijden — geen geluid, geen spraak.
    static func updateSpeedingPopup(speedKmh: Int?, limit: Int?, fine: FineEstimate) {
        guard let title = fine.carPlayNotificationTitle(speedKmh: speedKmh, limit: limit) else {
            clearSpeedingPopup()
            return
        }

        guard !CarPlaySessionTracker.isForegroundOnCarPlay else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = fine.carPlayNotificationSubtitle(speedKmh: speedKmh, limit: limit) ?? ""
        content.body = fine.displayText(speedKmh: speedKmh, limit: limit) ?? ""
        content.sound = nil
        content.categoryIdentifier = speedingCategoryId
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let request = UNNotificationRequest(
            identifier: speedingNotificationId,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func clearSpeedingPopup() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [speedingNotificationId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [speedingNotificationId])
    }

    /// Gesproken waarschuwing via autoradio — alleen voor flitsers, niet voor boetes.
    static func speakFlitser(alert: NearbyAlert) {
        guard speechEnabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSpokenAt) >= 20 else { return }
        guard shouldSpeakInCar() else { return }
        lastSpokenAt = now

        configureSpeechAudioSession()

        let text = "Let op. \(alert.label). \(Self.spokenDistance(for: alert))"
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "nl-NL")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.preUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }


    private static func distanceCopy(for alert: NearbyAlert) -> String {
        if let road = alert.roadContextText {
            return "\(road) - over \(alert.distance_m) meter"
        }
        return "Over \(alert.distance_m) meter"
    }

    private static func spokenDistance(for alert: NearbyAlert) -> String {
        let kind = alert.alert_kind ?? alert.type
        let prefix: String
        switch kind {
        case "average", "trajectcontrole":
            prefix = "Traject over"
        case "jam", "file":
            prefix = "File over"
        case "mobile", "flitser_mobiel", "politie":
            prefix = "Mobiele controle over"
        default:
            prefix = "Over"
        }
        if let road = alert.roadContextText {
            return "\(road). \(prefix) \(alert.distance_m) meter."
        }
        return "\(prefix) \(alert.distance_m) meter."
    }

    static func setSpeechEnabled(_ enabled: Bool) {
        speechEnabled = enabled
        if !enabled {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private static func registerCategories() {
        let flitser = UNNotificationCategory(
            identifier: flitserCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: [.allowInCarPlay]
        )
        let speeding = UNNotificationCategory(
            identifier: speedingCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: [.allowInCarPlay]
        )
        UNUserNotificationCenter.current().setNotificationCategories([flitser, speeding])
    }

    private static func shouldSpeakInCar() -> Bool {
        if CarPlaySessionTracker.isForegroundOnCarPlay { return true }
        return isCarAudioOutput()
    }

    private static func isCarAudioOutput() -> Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        return route.outputs.contains { output in
            switch output.portType {
            case .carAudio, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                return true
            default:
                return false
            }
        }
    }

    private static func configureSpeechAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true, options: [])
    }
}
