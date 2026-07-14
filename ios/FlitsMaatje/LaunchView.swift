import SwiftUI

struct LaunchView: View {
    @State private var isRunning = false
    @State private var location: LocationBackgroundService?
    @State private var statusMessage = "Klaar om te rijden"

    var body: some View {
        Group {
            if isRunning, let location {
                ContentView()
                    .environmentObject(location)
                    .onChange(of: location.currentAlert) { _, alert in
                        CarPlayDrivingTaskCoordinator.shared.update(alert: alert)
                    }
            } else {
                VStack(spacing: 28) {
                    Text("FlitsMaatje")
                        .font(.system(size: 34, weight: .bold))
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button(action: start) {
                        Text("Start")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
    }

    private func start() {
        statusMessage = "Bezig met starten…"
        AppLogger.install()
        AppLogger.enableUIUpdates()

        let service = LocationBackgroundService()
        location = service
        isRunning = true

        Task { @MainActor in
            AppLogger.markBootStage("user-started")
            try? await Task.sleep(nanoseconds: 300_000_000)
            service.requestPermissionAndStart()
            try? await Task.sleep(nanoseconds: 400_000_000)
            service.activateWhenReady()
            CarPlayDrivingTaskCoordinator.shared.locationService = service
            AppLogger.markBootStage("user-started-complete")
            AppLogger.uploadLogFile(reason: "started")
        }
    }
}
