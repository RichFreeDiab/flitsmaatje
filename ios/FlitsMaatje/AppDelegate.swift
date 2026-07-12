import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppLogger.install()
        AppLogger.log("AppDelegate didFinishLaunching")
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            AppLogger.log("Scene config: CarPlay")
            return UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
        }
        AppLogger.log("Scene config: Default")
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AppLogger.log("App actief")
        AppLogger.uploadLogFile(reason: "active")
    }

    func applicationWillResignActive(_ application: UIApplication) {
        AppLogger.log("App inactief")
        AppLogger.flush()
        AppLogger.uploadLogFile(reason: "background")
    }
}
