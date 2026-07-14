import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BootLogger.mark("didFinishLaunching")
        AppLogger.install()
        BootLogger.mark("logger-installed")
        BootLogger.uploadAsync()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            BootLogger.mark("scene-config-carplay")
            return UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
        }
        BootLogger.mark("scene-config-phone")
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        BootLogger.mark("didBecomeActive")
        AppLogger.markBootStage("didBecomeActive")
        BootLogger.uploadAsync()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        BootLogger.mark("willResignActive")
        AppLogger.flush()
        BootLogger.uploadAsync()
    }
}
