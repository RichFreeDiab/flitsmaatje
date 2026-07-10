import ActivityKit
import CoreLocation
import SwiftUI
import UIKit
import WidgetKit

@main
struct FlitsMaatjeApp: App {
    @StateObject private var locationService = LocationBackgroundService()
    @StateObject private var navigationService = NavigationService()

    init() {
        AppLogger.install()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        AppLogger.log("FlitsMaatje start — iOS \(UIDevice.current.systemVersion), v\(version) (\(build))")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(locationService)
                .environmentObject(navigationService)
        }
    }
}
