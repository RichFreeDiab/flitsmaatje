import UIKit

@main
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Async only — sync upload + semaphore on a utility queue raced with
        // button-tap uploads and contributed to main-thread stalls.
        BootLogger.uploadAsync()
    }
}
