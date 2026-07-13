import SwiftUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        BootLogger.mark("phone-scene-willConnect")

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
              let location = appDelegate.locationService else {
            BootLogger.mark("phone-scene-NO-LOCATION")
            return
        }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(
            rootView: RootView()
                .environmentObject(location)
        )
        self.window = window
        window.makeKeyAndVisible()
        BootLogger.mark("phone-window-visible")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        BootLogger.mark("phone-scene-active")
    }
}
