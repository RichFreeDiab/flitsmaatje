import SwiftUI

@MainActor
struct LaunchView: View {
    @State private var phase: Phase = .idle
    @State private var location: LocationBackgroundService?
    @State private var navigationService: NavigationService?
    @State private var statusMessage = "Klaar om te rijden"
    @State private var showLocationHelp = false
    @State private var showAbout = false
    @State private var carPlayAutostartRequested = false
    @State private var startupStarted = false

    private enum Phase {
        case idle
        case running
        case dashboard
        case navigation
    }

    var body: some View {
        Group {
            switch phase {
            case .idle:
                idleView
            case .running:
                if let location {
                    RunningShellView(
                        location: location,
                        onOpenDashboard: {
                            BootLogger.mark("dashboard-tap")
                            phase = .dashboard
                        },
                        onOpenMap: openMap
                    )
                } else {
                    idleView
                }
            case .dashboard:
                if let location {
                    ContentView()
                        .environmentObject(location)
                        .onAppear { BootLogger.mark("dashboard-visible") }
                }
            case .navigation:
                if let location, let navigationService {
                    NavigationMapView()
                        .environmentObject(location)
                        .environmentObject(navigationService)
                        .onAppear { BootLogger.mark("navigation-visible") }
                } else if let location {
                    RunningShellView(location: location, onOpenDashboard: { phase = .dashboard }, onOpenMap: openMap)
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
                        Label("Start", systemImage: "speedometer")
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

    private func startDriving() {
        BootLogger.mark("start-tap")
        startGPS()
    }

    /// GPS + eenvoudig snelheidsscherm. Geen SwiftUI-Map, geen NavigationService
    /// en geen CarPlay-coordinator in dezelfde tik — dat crashte 553–592.
    private func startGPS() {
        guard !startupStarted else { return }
        startupStarted = true
        BootLogger.mark("gps-tap")

        let service = LocationBackgroundService.shared
        BootLogger.mark("gps-location-shared")
        location = service
        phase = .running
        BootLogger.mark("phase-running")
        BootLogger.uploadAsync()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            BootLogger.mark("gps-deferred-activate")
            service.prepareForUse()
            BootLogger.mark("gps-prepared")
            if !service.isTracking {
                service.activateForegroundOnly()
            }
            BootLogger.mark("gps-active")
            service.markRuntimeReady()
            BootLogger.mark("gps-ready")
            BootLogger.uploadAsync()
        }
    }

    private func openMap() {
        BootLogger.mark("map-tap")
        let service = location ?? LocationBackgroundService.shared
        location = service
        let nav = NavigationService.shared
        navigationService = nav
        CarPlayNavigationCoordinator.shared.navigationService = nav
        CarPlayNavigationCoordinator.shared.locationService = service
        phase = .navigation
    }
}

private struct RunningShellView: View {
    @ObservedObject var location: LocationBackgroundService
    let onOpenDashboard: () -> Void
    let onOpenMap: () -> Void

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

            if let alert = location.currentAlert {
                Text("\(alert.label) over \(alert.distance_m) m")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Open dashboard", action: onOpenDashboard)
                .buttonStyle(.borderedProminent)

            Button("Kaart openen", action: onOpenMap)
                .buttonStyle(.bordered)

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
        .onAppear { BootLogger.mark("running-visible") }
    }
}
