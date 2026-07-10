import ActivityKit
import CoreLocation
import SwiftUI
import WidgetKit

@main
struct FlitsMaatjeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var locationService = LocationBackgroundService()
    @StateObject private var navigationService = NavigationService()

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        AppLogger.log("FlitsMaatje init — v\(version) (\(build))")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(locationService)
                .environmentObject(navigationService)
        }
    }
}
