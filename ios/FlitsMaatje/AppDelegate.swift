import UIKit

@main
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BootLogger.mark("did-finish-launching")
        AppLogger.install()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        BootLogger.mark("did-become-active")
        BootLogger.uploadAsync()
    }
}
