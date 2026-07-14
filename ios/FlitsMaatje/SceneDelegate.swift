import SwiftUI
import UIKit

/// iOS 26 + CarPlay vereist een phone SceneDelegate die zelf het venster maakt.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        BootLogger.mark("phone-scene-willConnect")

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: RootView())
        self.window = window
        window.makeKeyAndVisible()
        BootLogger.mark("phone-window-visible")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        BootLogger.mark("phone-scene-active")
        BootLogger.uploadAsync()
    }
}
