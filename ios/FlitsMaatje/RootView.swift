import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var location: LocationBackgroundService?
    @State private var didBootstrap = false

    var body: some View {
        Group {
            if let location {
                ContentView()
                    .environmentObject(location)
                    .onChange(of: scenePhase) { _, phase in
                        AppLogger.markBootStage("scenePhase-\(phase)")
                        if phase == .active {
                            location.activateWhenReady()
                            BootLogger.uploadAsync()
                        } else if phase == .background {
                            AppLogger.flush()
                            BootLogger.uploadAsync()
                        }
                    }
                    .onChange(of: location.currentAlert) { _, alert in
                        CarPlayDrivingTaskCoordinator.shared.update(alert: alert)
                    }
            } else {
                VStack(spacing: 16) {
                    Text("FlitsMaatje")
                        .font(.largeTitle.bold())
                    ProgressView("Starten…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            BootLogger.mark("rootview-onAppear")
            bootstrapIfNeeded()
        }
    }

    private func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        BootLogger.mark("bootstrap-start")
        AppLogger.enableUIUpdates()
        AppLogger.markBootStage("rootview-ready")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            let service = LocationBackgroundService()
            location = service
            BootLogger.mark("location-created")
            CarPlayDrivingTaskCoordinator.shared.locationService = service
            BootLogger.uploadAsync()

            try? await Task.sleep(nanoseconds: 400_000_000)
            service.requestPermissionAndStart()
            if scenePhase == .active {
                service.activateWhenReady()
            }
            BootLogger.mark("bootstrap-complete")
            BootLogger.uploadAsync()
        }
    }
}
