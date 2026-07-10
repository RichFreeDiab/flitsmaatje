import SwiftUI

struct RootView: View {
    @EnvironmentObject private var location: LocationBackgroundService
    @EnvironmentObject private var navigation: NavigationService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Label("Status", systemImage: "gauge.with.dots.needle.67percent")
                }
                .tag(0)

            Group {
                if selectedTab == 1 {
                    NavigationMapView()
                } else {
                    Color(.systemBackground)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "map")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Tik op Navigatie voor de kaart")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .tabItem {
                Label("Navigatie", systemImage: "map.fill")
            }
            .tag(1)
        }
        .onAppear {
            AppLogger.log("RootView verschijnt (tab \(selectedTab))")
            CarPlayDrivingTaskCoordinator.shared.locationService = location
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                location.requestPermissionAndStart()
            }
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
