import CarPlay
import Foundation

/// CarPlay "Driving Task" UI: een glanceable lijst + een enkel-tap alert.
///
/// Belangrijk: géén kaart, géén zoek, géén routeplanning; alleen meldingen die direct relevant zijn voor de rijtaak.
@MainActor
final class CarPlayDrivingTaskCoordinator: NSObject {
    static let shared = CarPlayDrivingTaskCoordinator()

    weak var locationService: LocationBackgroundService?

    private(set) weak var interfaceController: CPInterfaceController?
    private var listTemplate: CPListTemplate?
    private var lastPresentedAlertId: String?

    func attach(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        let template = makeListTemplate(alert: locationService?.currentAlert)
        self.listTemplate = template
        interfaceController.setRootTemplate(template, animated: false)
    }

    func detach() {
        interfaceController = nil
        listTemplate = nil
        lastPresentedAlertId = nil
    }

    func update(alert: NearbyAlert?) {
        guard let interfaceController else { return }

        if let template = listTemplate {
            template.updateSections(makeSections(alert: alert))
        } else {
            let template = makeListTemplate(alert: alert)
            listTemplate = template
            interfaceController.setRootTemplate(template, animated: false)
        }

        presentAlertIfNeeded(alert)
    }

    private func presentAlertIfNeeded(_ alert: NearbyAlert?) {
        guard let alert else {
            lastPresentedAlertId = nil
            return
        }
        guard lastPresentedAlertId != alert.id else { return }
        lastPresentedAlertId = alert.id

        let alertTemplate = CPAlertTemplate(
            titleVariants: ["\(alert.icon) \(alert.label)"],
            actions: [
                CPAlertAction(title: "OK", style: .default) { _ in }
            ]
        )
        alertTemplate.subtitleVariants = ["Over \(alert.distance_m) m"]

        interfaceController?.presentTemplate(alertTemplate, animated: true)

        // Auto-dismiss zodat het geen modal "trap" wordt.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            try? await interfaceController?.dismissTemplate(animated: true)
        }
    }

    private func makeListTemplate(alert: NearbyAlert?) -> CPListTemplate {
        let template = CPListTemplate(
            title: "FlitsMaatje",
            sections: makeSections(alert: alert)
        )
        template.tabTitle = "Flitsers"
        template.tabImage = UIImage(systemName: "exclamationmark.triangle.fill")
        return template
    }

    private func makeSections(alert: NearbyAlert?) -> [CPListSection] {
        if let alert {
            let item = CPListItem(
                text: "\(alert.icon) \(alert.label)",
                detailText: "Over \(alert.distance_m) m"
            )
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    self?.presentAlertIfNeeded(alert)
                    completion()
                }
            }
            return [CPListSection(items: [item], header: "Dichtstbijzijnde melding", sectionIndexTitle: nil)]
        }

        let item = CPListItem(text: "Geen meldingen in de buurt", detailText: nil)
        item.isEnabled = false
        return [CPListSection(items: [item], header: nil, sectionIndexTitle: nil)]
    }
}

