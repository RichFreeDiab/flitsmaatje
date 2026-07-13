import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppLogger.install()
        AppLogger.markBootStage("didFinishLaunching")
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AppLogger.markBootStage("didBecomeActive")
        AppLogger.uploadLogFile(reason: "active")
    }

    func applicationWillResignActive(_ application: UIApplication) {
        AppLogger.markBootStage("willResignActive")
        AppLogger.flush()
        AppLogger.uploadLogFile(reason: "background")
    }
}
