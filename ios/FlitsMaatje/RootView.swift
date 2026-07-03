import SwiftUI

struct RootView: View {
    @EnvironmentObject private var location: LocationBackgroundService
    @EnvironmentObject private var navigation: NavigationService

    var body: some View {
        TabView {
            NavigationMapView()
                .tabItem {
                    Label("Navigatie", systemImage: "map.fill")
                }

            ContentView()
                .tabItem {
                    Label("Status", systemImage: "gauge.with.dots.needle.67percent")
                }
        }
        .onAppear {
            CarPlayNavigationCoordinator.shared.locationService = location
            CarPlayNavigationCoordinator.shared.navigationService = navigation
            location.requestPermissionAndStart()
        }
        .onChange(of: navigation.route?.distance) { _, _ in
            CarPlayNavigationCoordinator.shared.syncFromPhoneNavigation()
        }
        .onChange(of: location.currentAlert) { _, alert in
            if let alert {
                CarPlayNavigationCoordinator.shared.handleFlitserAlert(alert)
            } else {
                CarPlayNavigationCoordinator.shared.clearFlitserAlertState()
            }
        }
        .onChange(of: location.lastLocation) { _, newLocation in
            guard let newLocation else { return }
            navigation.updateProgress(location: newLocation)
            CarPlayNavigationCoordinator.shared.updateNavigationProgress()
        }
        .onChange(of: location.isTracking) { _, tracking in
            if !tracking {
                navigation.stopNavigation()
            }
        }
    }
}
