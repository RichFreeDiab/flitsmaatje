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
            CarPlaySessionTracker.setForegroundOnCarPlay(true)

            // Eén gedeelde GPS-service — tweede CLLocationManager veroorzaakte
            // dubbele updates en CarPlay-sessie-crashes bij herberekenen.
            let locationService = LocationBackgroundService.shared
            let navigationService = NavigationService.shared
            self.locationService = locationService
            self.navigationService = navigationService

            locationService.prepareForUse()
            if !locationService.isTracking {
                locationService.activateWhenReady()
                locationService.start()
            }

            window.tintColor = .systemBlue

            let mapViewController = CarPlayMapViewController()
            self.mapViewController = mapViewController
            window.rootViewController = mapViewController

            let mapTemplate = CPMapTemplate()
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

            locationHandlerId = locationService.addLocationUpdateHandler { [weak self] location in
                // Alleen CarPlay-kaart volgen; nav-progress is centraal afgehandeld.
                self?.mapViewController?.follow(location: location)
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
            // Stop géén shared GPS/navigatie — telefoon blijft rijden.
            CarPlayNavigationCoordinator.shared.detach()
            CarPlayDrivingTaskCoordinator.shared.detach()
            self.locationService = nil
            self.navigationService = nil
            self.mapViewController = nil
            AppLogger.log("CarPlay disconnect")
        }
    }
}
