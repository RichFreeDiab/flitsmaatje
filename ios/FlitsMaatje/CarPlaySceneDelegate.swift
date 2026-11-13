import CarPlay
import CoreLocation
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var mapViewController: CarPlayMapViewController?
    private var locationService: LocationBackgroundService?
    private var navigationService: NavigationService?
    private var locationHandlerId: UUID?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            AppLogger.log("CarPlay connect")
            BootLogger.mark("carplay-connect")
            CarPlaySessionTracker.setForegroundOnCarPlay(true)

            // Alleen shared services + UI. GPS-activate gebeurt via LaunchView
            // (startForCarPlayIfNeeded) of zachte fallback hieronder — geen race.
            let locationService = LocationBackgroundService.shared
            let navigationService = NavigationService.shared
            self.locationService = locationService
            self.navigationService = navigationService

            locationService.prepareForUse()
            BootLogger.mark("carplay-prepared")

            window.tintColor = .systemBlue

            let mapViewController = CarPlayMapViewController()
            self.mapViewController = mapViewController
            window.rootViewController = mapViewController

            let mapTemplate = CPMapTemplate()
            // Geen await in deze Task — anders eist nieuwe CarPlay-SDK try/await op setRootTemplate.
            interfaceController.setRootTemplate(mapTemplate, animated: false)

            CarPlayNavigationCoordinator.shared.locationService = locationService
            CarPlayNavigationCoordinator.shared.navigationService = navigationService
            CarPlayNavigationCoordinator.shared.attach(
                template: mapTemplate,
                mapViewController: mapViewController,
                interfaceController: interfaceController
            )

            CarPlayDrivingTaskCoordinator.shared.locationService = locationService
            CarPlayDrivingTaskCoordinator.shared.attach(interfaceController: interfaceController, mapViewController: mapViewController)
            BootLogger.mark("carplay-ui-attached")

            locationHandlerId = locationService.addLocationUpdateHandler { [weak self] location in
                self?.mapViewController?.follow(location: location)
                DriveSession.shared.syncSnapshot(
                    alertId: locationService.currentAlert?.id,
                    speedKmh: locationService.currentSpeedKmh,
                    course: location.course
                )
            }

            // Als de telefoon-UI niet autostart, start GPS veilig na korte delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if !locationService.isTracking, locationService.beginExclusiveStartup() {
                    BootLogger.mark("carplay-fallback-activate")
                    locationService.activateForegroundOnly()
                    locationService.markRuntimeReady()
                }
                BootLogger.mark("carplay-connect-done")
            }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            CarPlaySessionTracker.setForegroundOnCarPlay(false)
            self.locationService?.removeLocationUpdateHandler(self.locationHandlerId)
            self.locationHandlerId = nil
            // Stop geen shared GPS/navigatie — telefoon blijft rijden.
            CarPlayNavigationCoordinator.shared.detach()
            CarPlayDrivingTaskCoordinator.shared.detach()
            self.locationService = nil
            self.navigationService = nil
            self.mapViewController = nil
            AppLogger.log("CarPlay disconnect")
        }
    }
}
