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
        DispatchQueue.global(qos: .utility).async {
            BootLogger.uploadSync(timeout: 3)
        }
    }
}
