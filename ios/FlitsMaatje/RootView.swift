import SwiftUI

/// Stelt zware services uit tot de UI-scene actief is (voorkomt opstart-crashes).
@MainActor
final class LaunchCoordinator: ObservableObject {
    @Published private(set) var location: LocationBackgroundService?
    private var didBootstrap = false

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        BootLogger.mark("bootstrap-start")
        AppLogger.enableUIUpdates()
        AppLogger.markBootStage("rootview-ready")

        let service = LocationBackgroundService()
        location = service
        BootLogger.mark("location-created")
        CarPlayDrivingTaskCoordinator.shared.locationService = service
        BootLogger.uploadSync()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            service.requestPermissionAndStart()
            service.activateWhenReady()
            AppLogger.markBootStage("bootstrap-complete")
            BootLogger.mark("bootstrap-complete")
            BootLogger.uploadSync()
            AppLogger.uploadLogFile(reason: "boot")
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var launch = LaunchCoordinator()

    var body: some View {
        Group {
            if let location = launch.location {
                ContentView()
                    .environmentObject(location)
                    .onChange(of: scenePhase) { _, phase in
                        AppLogger.markBootStage("scenePhase-\(phase)")
                        if phase == .active {
                            location.activateWhenReady()
                            AppLogger.uploadLogFile(reason: "scene-active")
                            BootLogger.uploadSync()
                        } else if phase == .background {
                            AppLogger.flush()
                            AppLogger.uploadLogFile(reason: "scene-background")
                            BootLogger.uploadSync()
                        }
                    }
                    .onChange(of: location.currentAlert) { _, alert in
                        CarPlayDrivingTaskCoordinator.shared.update(alert: alert)
                    }
            } else {
                ProgressView("FlitsMaatje starten…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { launch.bootstrapIfNeeded() }
    }
}
