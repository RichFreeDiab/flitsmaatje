import SwiftUI

@MainActor
struct LaunchView: View {
    @State private var phase: Phase = .idle
    @State private var location: LocationBackgroundService?
    @State private var statusMessage = "Klaar om te rijden"

    private enum Phase {
        case idle
        case armed
        case gpsStarting
        case running
        case dashboard
    }

    var body: some View {
        switch phase {
        case .idle:
            idleView
        case .armed:
            armedView
        case .gpsStarting:
            VStack(spacing: 20) {
                ProgressView()
                Text(statusMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .running:
            if let location {
                RunningShellView(location: location) {
                    AppLogger.install()
                    AppLogger.enableUIUpdates()
                    phase = .dashboard
                }
            }
        case .dashboard:
            if let location {
                ContentView()
                    .environmentObject(location)
                    .onAppear {
                        CarPlayDrivingTaskCoordinator.shared.locationService = location
                    }
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 28) {
            Text("FlitsMaatje")
                .font(.system(size: 34, weight: .bold))
            Text(statusMessage)
                .foregroundStyle(.secondary)
            Button(action: armApp) {
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

    private var armedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("App is gestart")
                .font(.title2.bold())
            Text("Tik hieronder om GPS te activeren.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: startGPS) {
                Text("GPS inschakelen")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Stap 1: alleen UI — geen logger, geen GPS, geen zware objecten.
    private func armApp() {
        BootLogger.mark("start-tap")
        BootLogger.uploadAsync()
        phase = .armed
    }

    /// Stap 2: GPS pas na bevestiging.
    private func startGPS() {
        phase = .gpsStarting
        statusMessage = "GPS voorbereiden…"
        BootLogger.mark("gps-tap")

        Task {
            BootLogger.mark("gps-before-service")
            let service = LocationBackgroundService()
            location = service
            BootLogger.mark("gps-service-created")

            statusMessage = "Locatie toestemming…"
            service.prepareForUse()
            BootLogger.mark("gps-prepared")

            try? await Task.sleep(nanoseconds: 600_000_000)

            statusMessage = "GPS starten…"
            service.activateForegroundOnly()
            BootLogger.mark("gps-active")

            try? await Task.sleep(nanoseconds: 400_000_000)
            BootLogger.uploadAsync()
            phase = .running
        }
    }
}

private struct RunningShellView: View {
    @ObservedObject var location: LocationBackgroundService
    let onOpenDashboard: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: location.isTracking ? "location.fill" : "location.slash")
                .font(.system(size: 48))
                .foregroundStyle(location.isTracking ? .green : .orange)

            Text(location.statusText)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let speed = location.currentSpeedKmh {
                Text("\(speed) km/u")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
            }

            Button("Open dashboard", action: onOpenDashboard)
                .buttonStyle(.borderedProminent)

            if location.managerAuthorizationIsWhenInUse {
                Button("Zet locatie op Altijd (CarPlay)") {
                    location.requestAlwaysPermission()
                }
                .font(.footnote)
            } else if location.managerAuthorizationIsAlways {
                Button("Achtergrond-tracking aanzetten") {
                    location.enableBackgroundTrackingIfAuthorized()
                }
                .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
