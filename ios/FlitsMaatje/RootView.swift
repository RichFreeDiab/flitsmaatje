import SwiftUI

struct RootView: View {
    @EnvironmentObject private var location: LocationBackgroundService
    @EnvironmentObject private var navigation: NavigationService

    var body: some View {
        TabView {
            NavigationMapView()
                .tabItem {
                    Label("Navigatie", systemImage: "map.fill")
                }

            ContentView()
                .tabItem {
                    Label("Status", systemImage: "gauge.with.dots.needle.67percent")
                }
        }
        .onAppear {
            CarPlayDrivingTaskCoordinator.shared.locationService = location
            location.requestPermissionAndStart()
        }
        .onChange(of: location.currentAlert) { _, alert in
            CarPlayDrivingTaskCoordinator.shared.update(alert: alert)
        }
        .onChange(of: location.fineEstimate) { _, _ in
            CarPlayDrivingTaskCoordinator.shared.updateSpeeding(
                speedKmh: location.currentSpeedKmh,
                limit: location.speedLimit,
                fine: location.fineEstimate
            )
        }
        .onChange(of: location.currentSpeedKmh) { _, _ in
            CarPlayDrivingTaskCoordinator.shared.updateSpeeding(
                speedKmh: location.currentSpeedKmh,
                limit: location.speedLimit,
                fine: location.fineEstimate
            )
        }
        .onChange(of: location.lastLocation) { _, newLocation in
            guard let newLocation else { return }
            navigation.updateProgress(location: newLocation)
        }
        .onChange(of: location.isTracking) { _, tracking in
            if !tracking {
                navigation.stopNavigation()
            }
        }
    }
}
