import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private let mapViewController = CarPlayMapViewController()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        window.rootViewController = mapViewController

        let mapTemplate = CPMapTemplate()
        interfaceController.setRootTemplate(mapTemplate, animated: false)

        Task { @MainActor in
            CarPlayNavigationCoordinator.shared.attach(
                template: mapTemplate,
                mapViewController: mapViewController,
                interfaceController: interfaceController
            )
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        Task { @MainActor in
            CarPlayNavigationCoordinator.shared.detach()
        }
    }
}
