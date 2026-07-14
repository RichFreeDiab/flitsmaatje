import UIKit

@main
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BootLogger.mark("didFinishLaunching")
        DispatchQueue.global(qos: .utility).async {
            BootLogger.uploadSync(timeout: 4)
        }
        AppLogger.install()
        BootLogger.mark("logger-installed")
        return true
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
