import SwiftUI

/// Minimale opstart — geen GPS, geen CarPlay, geen logging tot de gebruiker start.
struct LaunchView: View {
    @State private var isRunning = false
    @State private var location: LocationBackgroundService?

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
                    Text("Klaar om te rijden")
                        .foregroundStyle(.secondary)
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
        AppLogger.install()
        AppLogger.enableUIUpdates()
        let service = LocationBackgroundService()
        location = service
        isRunning = true
        CarPlayDrivingTaskCoordinator.shared.locationService = service
        service.requestPermissionAndStart()
        service.activateWhenReady()
        AppLogger.markBootStage("user-started")
    }
}
