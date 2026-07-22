import SwiftUI

@MainActor
struct LaunchView: View {
    @State private var phase: Phase = .idle
    @State private var location: LocationBackgroundService?
    @State private var navigationService: NavigationService?
    @State private var statusMessage = "Klaar om te rijden"
    @State private var openNavigationAfterGPS = false
    @State private var showLocationHelp = false
    @State private var showAbout = false
    @State private var carPlayAutostartRequested = false

    private enum Phase {
        case idle
        case armed
        case gpsStarting
        case running
        case dashboard
        case navigation
    }

    var body: some View {
        Group {
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
                    BootLogger.mark("dashboard-tap")
                    phase = .dashboard
                }
            }
        case .dashboard:
            if let location {
                ContentView()
                    .environmentObject(location)
                    .onAppear {
                        BootLogger.mark("dashboard-visible")
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            CarPlayDrivingTaskCoordinator.shared.locationService = location
                        }
                    }
            }
        case .navigation:
            if let location, let navigationService {
                NavigationMapView()
                    .environmentObject(location)
                    .environmentObject(navigationService)
            }
            }
        }
        .onAppear {
            startForCarPlayIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .flitsMaatjeCarPlayConnectionChanged)) { notification in
            if (notification.object as? Bool) == true {
                startForCarPlayIfNeeded()
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FlitsMaatje")
                    .font(.title2.bold())
                Spacer()
                Menu {
                    Button(action: armApp) {
                        Label("Snelheidsdashboard", systemImage: "speedometer")
                    }
                    Button(action: openNavigation) {
                        Label("Navigatie", systemImage: "map")
                    }
                    Divider()
                    Button { showLocationHelp = true } label: {
                        Label("GPS & CarPlay", systemImage: "car.fill")
                    }
                    Button { showAbout = true } label: {
                        Label("Over FlitsMaatje", systemImage: "info.circle")
                    }
                } label: {
                    Label("Menu", systemImage: "line.3.horizontal")
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Navigatiemenu")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))

            Spacer()

            VStack(spacing: 28) {
                Image(systemName: "speedometer")
                    .font(.system(size: 54))
                    .foregroundStyle(.blue)
                Text("Klaar om te rijden")
                    .font(.title2.bold())
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

                Button(action: openNavigation) {
                    Label("Navigatie openen", systemImage: "map")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .alert("GPS & CarPlay", isPresented: $showLocationHelp) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Start de app en geef locatietoestemming. Kies daarna in Instellingen > CarPlay > jouw auto > Widgets voor FlitsMaatje.")
        }
        .alert("Over FlitsMaatje", isPresented: $showAbout) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Snelheid, snelheidslimiet, flitsers en navigatie in één app.")
        }
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

    /// CarPlay mag de rijmodus meteen starten zodra de CarPlay-scène
    /// door iOS is verbonden. De gebruiker hoeft dan niet eerst op Start te tikken.
    private func startForCarPlayIfNeeded() {
        guard CarPlaySessionTracker.isForegroundOnCarPlay,
              !carPlayAutostartRequested,
              location == nil else { return }
        carPlayAutostartRequested = true
        openNavigationAfterGPS = false
        startGPS()
    }

    /// Stap 1: alleen UI — geen logger, geen GPS, geen zware objecten.
    private func armApp() {
        openNavigationAfterGPS = false
        BootLogger.mark("start-tap")
        BootLogger.uploadAsync()
        phase = .armed
    }

    private func openNavigation() {
        openNavigationAfterGPS = true
        startGPS()
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
            navigationService = NavigationService()
            // CarPlay may connect before the phone dashboard is opened. Keep the
            // shared coordinator connected to the live GPS service immediately.
            CarPlayDrivingTaskCoordinator.shared.locationService = service
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
            phase = openNavigationAfterGPS ? .navigation : .running
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
