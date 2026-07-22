import CarPlay
import CoreLocation
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var mapViewController: CarPlayMapViewController?
    private var locationService: LocationBackgroundService?
    private var navigationService: NavigationService?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            AppLogger.log("CarPlay connect")
            CarPlaySessionTracker.isForegroundOnCarPlay = true

            let locationService = LocationBackgroundService()
            let navigationService = NavigationService()
            self.locationService = locationService
            self.navigationService = navigationService

            locationService.prepareForUse()
            locationService.activateWhenReady()
            locationService.start()

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
            CarPlayDrivingTaskCoordinator.shared.attach(interfaceController: interfaceController)

            locationService.onLocationUpdate = { [weak navigationService] location in
                navigationService?.updateProgress(location: location)
                CarPlayNavigationCoordinator.shared.updateNavigationProgress()
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

            CarPlaySessionTracker.isForegroundOnCarPlay = false
            self.locationService?.onLocationUpdate = nil
            self.navigationService?.stopNavigation()
            CarPlayNavigationCoordinator.shared.detach()
            CarPlayDrivingTaskCoordinator.shared.detach()
            self.locationService?.stop()
            self.locationService = nil
            self.navigationService = nil
            self.mapViewController = nil
            AppLogger.log("CarPlay disconnect")
        }
    }
}
