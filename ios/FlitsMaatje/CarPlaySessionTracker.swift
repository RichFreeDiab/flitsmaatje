import Foundation

extension Notification.Name {
    static let flitsMaatjeCarPlayConnectionChanged = Notification.Name(
        "nl.readvanes.flitsmaatje.carPlayConnectionChanged"
    )
}

/// Houdt bij of FlitsMaatje op het CarPlay-scherm actief is.
/// Zodra CarPlay de app-scène verbindt, wordt de telefoonweergave zonder
/// keuzescherm in rijmodus gezet.
enum CarPlaySessionTracker {
    private(set) static var isForegroundOnCarPlay = false

    static func setForegroundOnCarPlay(_ isConnected: Bool) {
        isForegroundOnCarPlay = isConnected
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .flitsMaatjeCarPlayConnectionChanged,
                object: isConnected
            )
        }
    }
}
