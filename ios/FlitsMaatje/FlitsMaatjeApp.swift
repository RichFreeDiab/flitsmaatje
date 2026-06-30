import ActivityKit
import CoreLocation
import SwiftUI
import WidgetKit

@main
struct FlitsMaatjeApp: App {
    @StateObject private var locationService = LocationBackgroundService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationService)
        }
    }
}
