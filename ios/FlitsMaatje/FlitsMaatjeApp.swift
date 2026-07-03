import ActivityKit
import CoreLocation
import SwiftUI
import WidgetKit

@main
struct FlitsMaatjeApp: App {
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
