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

        let template = makeListTemplate()
        self.listTemplate = template
        interfaceController.setRootTemplate(template, animated: false)
    }

    func detach() {
        interfaceController = nil
        listTemplate = nil
        lastPresentedAlertId = nil
    }

    func update(alert: NearbyAlert?) {
        guard interfaceController != nil else { return }
        refreshList()
        presentAlertIfNeeded(alert)
    }

    func updateSpeeding(speedKmh: Int?, limit: Int?, fine: FineEstimate?) {
        guard interfaceController != nil else { return }
        refreshList()
    }

    func clearSpeeding() {
        refreshList()
    }

    private func refreshList() {
        guard let interfaceController else { return }

        if let template = listTemplate {
            template.updateSections(makeSections())
        } else {
            let template = makeListTemplate()
            listTemplate = template
            interfaceController.setRootTemplate(template, animated: false)
        }
    }

    private func presentAlertIfNeeded(_ alert: NearbyAlert?) {
        guard let alert else {
            lastPresentedAlertId = nil
            return
        }
        guard lastPresentedAlertId != alert.id else { return }
        lastPresentedAlertId = alert.id

        let alertTemplate = CPAlertTemplate(
            titleVariants: ["\(alert.icon) \(alert.label) — over \(alert.distance_m) m"],
            actions: [
                CPAlertAction(title: "OK", style: .default) { _ in }
            ]
        )

        interfaceController?.presentTemplate(alertTemplate, animated: true)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            try? await interfaceController?.dismissTemplate(animated: true)
        }
    }

    private func presentSpeedingAlert(speedKmh: Int?, limit: Int?, fine: FineEstimate) {
        guard let body = fine.displayText(speedKmh: speedKmh, limit: limit) else { return }

        let alertTemplate = CPAlertTemplate(
            titleVariants: ["🚨 \(body)"],
            actions: [
                CPAlertAction(title: "OK", style: .default) { _ in }
            ]
        )

        interfaceController?.presentTemplate(alertTemplate, animated: true)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            try? await interfaceController?.dismissTemplate(animated: true)
        }
    }

    private func makeListTemplate() -> CPListTemplate {
        let template = CPListTemplate(
            title: "FlitsMaatje",
            sections: makeSections()
        )
        template.tabTitle = "Flitsers"
        template.tabImage = UIImage(systemName: "exclamationmark.triangle.fill")
        return template
    }

    private func makeSections() -> [CPListSection] {
        var sections: [CPListSection] = []

        if let speedKmh = locationService?.currentSpeedKmh,
           let limit = locationService?.speedLimit,
           let fine = locationService?.fineEstimate,
           let detail = fine.displayText(speedKmh: speedKmh, limit: limit) {
            let item = CPListItem(
                text: "🚨 Te hard rijden",
                detailText: detail
            )
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    self?.presentSpeedingAlert(speedKmh: speedKmh, limit: limit, fine: fine)
                    completion()
                }
            }
            sections.append(CPListSection(items: [item], header: "Snelheid", sectionIndexTitle: nil))
        }

        if let alert = locationService?.currentAlert {
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
            sections.append(CPListSection(items: [item], header: "Dichtstbijzijnde melding", sectionIndexTitle: nil))
        }

        if sections.isEmpty {
            let item = CPListItem(text: "Geen meldingen in de buurt", detailText: nil)
            item.isEnabled = false
            sections.append(CPListSection(items: [item], header: nil, sectionIndexTitle: nil))
        }

        return sections
    }
}
