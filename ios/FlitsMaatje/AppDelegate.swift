import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BootLogger.mark("didFinishLaunching")
        AppLogger.install()
        BootLogger.mark("logger-installed")
        BootLogger.uploadSync()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        BootLogger.mark("didBecomeActive")
        AppLogger.markBootStage("didBecomeActive")
        BootLogger.uploadSync()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        BootLogger.mark("willResignActive")
        AppLogger.flush()
        BootLogger.uploadSync()
    }
}
