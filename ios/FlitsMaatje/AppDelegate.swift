import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppLogger.install()
        AppLogger.log("AppDelegate didFinishLaunching")
        AppLogger.uploadLogFile(reason: "launch")
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let role = connectingSceneSession.role
        let name = role == .carTemplateApplication ? "CarPlay" : "Default Configuration"
        AppLogger.log("Scene verbinding: role=\(role.rawValue) config=\(name)")
        return UISceneConfiguration(name: name, sessionRole: role)
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        AppLogger.log("Scene sessies verwijderd: \(sceneSessions.count)")
    }
}
