import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        Task { @MainActor in
            CarPlaySessionTracker.isForegroundOnCarPlay = true
            CarPlayDrivingTaskCoordinator.shared.attach(interfaceController: interfaceController)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        Task { @MainActor in
            CarPlaySessionTracker.isForegroundOnCarPlay = false
            CarPlayDrivingTaskCoordinator.shared.detach()
        }
    }
}
