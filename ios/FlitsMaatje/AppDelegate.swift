import UIKit
import SwiftUI

@main
final class AppDelegate: NSObject, UIApplicationDelegate {
    var locationService: LocationBackgroundService!

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BootLogger.mark("didFinishLaunching")
        BootLogger.upload()
        AppLogger.install()
        locationService = LocationBackgroundService()
        BootLogger.mark("location-service-created")
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
        BootLogger.upload()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        BootLogger.mark("willResignActive")
        AppLogger.flush()
        BootLogger.upload()
    }
}
