import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var mapViewController: CarPlayMapViewController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        Task { @MainActor in
            CarPlaySessionTracker.isForegroundOnCarPlay = true
            let mapViewController = CarPlayMapViewController()
            self.mapViewController = mapViewController
            templateApplicationScene.carWindow.rootViewController = mapViewController

            let mapTemplate = CPMapTemplate()
            mapTemplate.title = "FlitsMaatje"
            mapTemplate.trailingNavigationBarButtons = [
                CPBarButton(title: "Mijn locatie") { [weak mapViewController] _ in
                    mapViewController?.recenter()
                }
            ]
            interfaceController.setRootTemplate(mapTemplate, animated: false)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        Task { @MainActor in
            CarPlaySessionTracker.isForegroundOnCarPlay = false
            CarPlayDrivingTaskCoordinator.shared.detach()
            self.mapViewController = nil
        }
    }
}
