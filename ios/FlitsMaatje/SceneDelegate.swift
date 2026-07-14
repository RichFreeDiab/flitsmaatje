import UIKit

/// Lege phone SceneDelegate — vereist op iOS 26 met CarPlay + meerdere scenes.
/// SwiftUI WindowGroup regelt het venster; deze class mag geen eigen UIWindow maken.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        BootLogger.mark("phone-scene-willConnect")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        BootLogger.mark("phone-scene-active")
        BootLogger.uploadAsync()
    }
}
