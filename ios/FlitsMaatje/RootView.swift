import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var location: LocationBackgroundService
    @State private var didBootstrap = false

    var body: some View {
        ContentView()
            .onAppear { bootstrapIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                AppLogger.markBootStage("scenePhase-\(phase)")
                if phase == .active {
                    location.activateWhenReady()
                    AppLogger.uploadLogFile(reason: "scene-active")
                } else if phase == .background {
                    AppLogger.flush()
                    AppLogger.uploadLogFile(reason: "scene-background")
                }
            }
            .onChange(of: location.currentAlert) { _, alert in
                CarPlayDrivingTaskCoordinator.shared.update(alert: alert)
            }
    }

    private func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        AppLogger.enableUIUpdates()
        AppLogger.markBootStage("rootview-ready")
        CarPlayDrivingTaskCoordinator.shared.locationService = location
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            location.requestPermissionAndStart()
            if scenePhase == .active {
                location.activateWhenReady()
            }
            AppLogger.uploadLogFile(reason: "boot")
        }
    }
}
