import SwiftUI

@MainActor
struct LaunchView: View {
    @State private var phase: Phase = .idle
    @State private var location: LocationBackgroundService?
    @State private var statusMessage = "Klaar om te rijden"

    private enum Phase {
        case idle
        case starting
        case running
        case dashboard
    }

    var body: some View {
        switch phase {
        case .idle:
            idleView
        case .starting:
            VStack(spacing: 20) {
                ProgressView()
                Text(statusMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .running, .dashboard:
            if let location {
                if phase == .dashboard {
                    ContentView()
                        .environmentObject(location)
                        .onAppear {
                            CarPlayDrivingTaskCoordinator.shared.locationService = location
                        }
                } else {
                    RunningShellView(location: location) {
                        phase = .dashboard
                    }
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

    private func start() {
        phase = .starting
        statusMessage = "Locatie voorbereiden…"

        Task {
            AppLogger.install()
            AppLogger.enableUIUpdates()
            AppLogger.markBootStage("user-started")
            AppLogger.flush()
            AppLogger.uploadLogFile(reason: "start-tap")

            let service = LocationBackgroundService()
            location = service

            statusMessage = "Toestemming controleren…"
            service.prepareForUse()
            try? await Task.sleep(nanoseconds: 400_000_000)

            statusMessage = "GPS starten…"
            service.activateForegroundOnly()
            try? await Task.sleep(nanoseconds: 800_000_000)

            AppLogger.markBootStage("user-started-complete")
            AppLogger.uploadLogFile(reason: "start-complete")
            phase = .running
        }
    }
}

/// Lichtgewicht scherm vóór het volledige dashboard — voorkomt crash bij zware UI.
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
