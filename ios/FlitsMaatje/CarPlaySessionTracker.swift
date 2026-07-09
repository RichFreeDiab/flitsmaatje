import Foundation

/// Houdt bij of FlitsMaatje op het CarPlay-scherm actief is (vs. een andere CarPlay-app zoals Flitsmeister).
@MainActor
enum CarPlaySessionTracker {
    static var isForegroundOnCarPlay = false
}
