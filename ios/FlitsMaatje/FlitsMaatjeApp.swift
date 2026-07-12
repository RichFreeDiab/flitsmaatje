import SwiftUI

@main
struct FlitsMaatjeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var locationService = LocationBackgroundService()
    @StateObject private var navigationService = NavigationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(locationService)
                .environmentObject(navigationService)
        }
    }
}
