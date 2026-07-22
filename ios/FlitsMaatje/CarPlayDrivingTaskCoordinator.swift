import CarPlay
import Foundation
import UIKit

/// CarPlay-status voor flits- en snelheidsmeldingen.
/// Meldingen blijven bewust niet-modale informatie: ze mogen nooit de actieve
/// navigatie van Apple Kaarten of een andere navigatie-app bedekken.
@MainActor
final class CarPlayDrivingTaskCoordinator: NSObject {
    static let shared = CarPlayDrivingTaskCoordinator()

    weak var locationService: LocationBackgroundService?

    private(set) weak var interfaceController: CPInterfaceController?
    private var listTemplate: CPListTemplate?
    private var lastLoggedAlertId: String?
    private var lastLoggedFineText: String?

    func attach(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        listTemplate = makeListTemplate()
    }

    func detach() {
        interfaceController = nil
        listTemplate = nil
        lastLoggedAlertId = nil
        lastLoggedFineText = nil
    }

    func update(alert: NearbyAlert?) {
        guard interfaceController != nil else { return }
        refreshList()
        guard let alert else {
            lastLoggedAlertId = nil
            return
        }
        guard lastLoggedAlertId != alert.id else { return }
        lastLoggedAlertId = alert.id
        AppLogger.log("CarPlay melding zonder pop-up: \(alert.label) op \(alert.distance_m)m")
    }

    func updateSpeeding(speedKmh: Int?, limit: Int?, fine: FineEstimate?) {
        guard interfaceController != nil else { return }
        refreshList()
        guard let fine, let text = fine.displayText(speedKmh: speedKmh, limit: limit) else {
            lastLoggedFineText = nil
            return
        }
        guard lastLoggedFineText != text else { return }
        lastLoggedFineText = text
        AppLogger.log("CarPlay snelheidsstatus zonder pop-up: \(text)")
    }

    func clearSpeeding() {
        lastLoggedFineText = nil
        refreshList()
    }

    private func refreshList() {
        if let template = listTemplate {
            template.updateSections(makeSections())
        } else {
            listTemplate = makeListTemplate()
        }
    }

    private func makeListTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "FlitsMaatje", sections: makeSections())
        template.tabTitle = "Flitsers"
        template.tabImage = UIImage(systemName: "exclamationmark.triangle.fill")
        return template
    }

    private func makeSections() -> [CPListSection] {
        var sections: [CPListSection] = []

        if let speed = locationService?.currentSpeedKmh,
           let limit = locationService?.speedLimit,
           let fine = locationService?.fineEstimate,
           let detail = fine.displayText(speedKmh: speed, limit: limit) {
            let item = CPListItem(text: "Snelheidswaarschuwing", detailText: detail)
            item.isEnabled = false
            sections.append(CPListSection(items: [item], header: "Snelheid", sectionIndexTitle: nil))
        }

        if let alert = locationService?.currentAlert {
            let item = CPListItem(text: "\(alert.icon) \(alert.label)", detailText: "Over \(alert.distance_m) m")
            item.isEnabled = false
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
