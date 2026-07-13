import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        BootLogger.mark("carplay-connected")
        Task { @MainActor in
            AppLogger.log("CarPlay: verbonden")
            CarPlaySessionTracker.isForegroundOnCarPlay = true
            CarPlayDrivingTaskCoordinator.shared.attach(interfaceController: interfaceController)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        Task { @MainActor in
            AppLogger.log("CarPlay: verbroken")
            CarPlaySessionTracker.isForegroundOnCarPlay = false
            CarPlayDrivingTaskCoordinator.shared.detach()
        }
    }
}
