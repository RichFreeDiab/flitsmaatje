import AudioToolbox
import Foundation
import UIKit
import UserNotifications

/// Geluid, trilling en lokale melding bij flitsers in de buurt.
enum AlertNotifier {
    private static var lastNotificationAt: Date = .distantPast

    static func requestPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func playFlitserAlarm() {
        AudioServicesPlaySystemSound(1057)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            AudioServicesPlaySystemSound(1057)
        }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    static func notifyFlitser(alert: NearbyAlert) {
        let now = Date()
        guard now.timeIntervalSince(lastNotificationAt) >= 20 else { return }
        lastNotificationAt = now

        let content = UNMutableNotificationContent()
        content.title = "FlitsMaatje — \(alert.label)"
        content.body = "Over \(alert.distance_m) meter"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "flits-\(alert.id)-\(Int(now.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
