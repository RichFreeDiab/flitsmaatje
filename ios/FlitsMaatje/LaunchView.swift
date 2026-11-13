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
    @State private var startupStarted = false

    private enum Phase {
        case idle
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
                    Button(action: startDriving) {
                        Label("Snelheidsdashboard", systemImage: "speedometer")
                    }
                    Button(action: startDriving) {
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
                Button(action: startDriving) {
                    Text("Start navigatie + meldingen")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
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
            Text("Snelheid, snelheidslimiet, flitsers en navigatie in een app.")
        }
    }

    private func startForCarPlayIfNeeded() {
        guard CarPlaySessionTracker.isForegroundOnCarPlay,
              !carPlayAutostartRequested,
              location == nil else { return }
        carPlayAutostartRequested = true
        startDriving()
    }

    /// Een tik: meteen GPS + navigatie. Geen tussen-scherm meer.
    private func startDriving() {
        openNavigationAfterGPS = true
        BootLogger.mark("start-tap")
        startGPS()
    }

    private func startGPS() {
        guard !startupStarted else { return }
        startupStarted = true
        phase = .gpsStarting
        statusMessage = "GPS voorbereiden..."
        BootLogger.mark("gps-tap")

        Task { @MainActor in
            BootLogger.mark("gps-before-service")
            let service = LocationBackgroundService.shared
            BootLogger.mark("gps-location-shared")

            guard service.beginExclusiveStartup() else {
                BootLogger.mark("gps-startup-busy")
                location = service
                navigationService = NavigationService.shared
                service.markRuntimeReady()
                phase = .navigation
                return
            }

            location = service
            BootLogger.mark("gps-location-assigned")

            statusMessage = "Locatie toestemming..."
            service.prepareForUse()
            BootLogger.mark("gps-prepared")

            let nav = NavigationService.shared
            BootLogger.mark("gps-nav-shared")
            navigationService = nav
            BootLogger.mark("gps-nav-assigned")

            CarPlayNavigationCoordinator.shared.navigationService = nav
            CarPlayNavigationCoordinator.shared.locationService = service
            CarPlayDrivingTaskCoordinator.shared.locationService = service
            BootLogger.mark("gps-service-created")

            statusMessage = "GPS starten..."
            BootLogger.mark("gps-before-activate")
            if !service.isTracking {
                service.activateForegroundOnly()
            }
            BootLogger.mark("gps-active")

            DriveSession.shared.markPhoneOwned(true)
            BootLogger.mark("gps-drive-session")

            service.markRuntimeReady()
            BootLogger.mark("gps-runtime-ready")

            DispatchQueue.global(qos: .utility).async {
                BootLogger.uploadAsync()
            }

            phase = openNavigationAfterGPS ? .navigation : .running
            BootLogger.mark(openNavigationAfterGPS ? "phase-navigation" : "phase-running")
            BootLogger.uploadAsync()
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
