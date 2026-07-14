import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var location: LocationBackgroundService?
    @State private var didBootstrap = false
    @State private var bootstrapError: String?

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
                VStack(spacing: 20) {
                    Text("FlitsMaatje")
                        .font(.largeTitle.bold())
                    if let bootstrapError {
                        Text(bootstrapError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        Button("Opnieuw proberen") {
                            didBootstrap = false
                            bootstrapError = nil
                            bootstrapIfNeeded()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        ProgressView("Starten…")
                    }
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
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard scenePhase == .active || scenePhase == .inactive else {
                BootLogger.mark("bootstrap-wait-scene")
                didBootstrap = false
                return
            }

            let service = LocationBackgroundService()
            location = service
            BootLogger.mark("location-created")
            CarPlayDrivingTaskCoordinator.shared.locationService = service
            BootLogger.uploadAsync()

            try? await Task.sleep(nanoseconds: 500_000_000)
            service.requestPermissionAndStart()
            service.activateWhenReady()
            BootLogger.mark("bootstrap-complete")
            BootLogger.uploadAsync()
        }
    }
}
