import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var location: LocationBackgroundService
    @EnvironmentObject private var navigation: NavigationService
    @State private var selectedTab = 0
    @State private var didBootstrap = false

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
            bootstrapIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            AppLogger.log("Scene phase: \(String(describing: phase))")
            if phase == .active {
                AppLogger.uploadLogFile(reason: "scene-active")
            } else if phase == .background {
                AppLogger.flush()
                AppLogger.uploadLogFile(reason: "scene-background")
            }
        }
        .onChange(of: location.currentAlert) { _, alert in
            CarPlayDrivingTaskCoordinator.shared.update(alert: alert)
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

    private func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        AppLogger.enableUIUpdates()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        AppLogger.log("RootView klaar — v\(version) (\(build))")
        CarPlayDrivingTaskCoordinator.shared.locationService = location
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            location.requestPermissionAndStart()
            AppLogger.uploadLogFile(reason: "boot")
        }
    }
}
