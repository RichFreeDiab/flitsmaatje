import CarPlay
import MapKit
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSearchTemplateDelegate {
    private var mapViewController: CarPlayMapViewController?
    private var locationService: LocationBackgroundService?
    private weak var interfaceController: CPInterfaceController?
    private weak var mapTemplate: CPMapTemplate?
    private var searchTemplate: CPSearchTemplate?
    private var navigationSession: CPNavigationSession?
    private var maneuvers: [CPManeuver] = []

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        Task { @MainActor in
            self.interfaceController = interfaceController
            CarPlaySessionTracker.isForegroundOnCarPlay = true

            let locationService = LocationBackgroundService()
            self.locationService = locationService
            locationService.prepareForUse()
            locationService.activateWhenReady()
            locationService.start()

            let mapViewController = CarPlayMapViewController()
            self.mapViewController = mapViewController
            window.rootViewController = mapViewController

            let mapTemplate = CPMapTemplate()
            self.mapTemplate = mapTemplate
            mapTemplate.trailingNavigationBarButtons = [
                CPBarButton(title: "Zoeken") { [weak self] _ in self?.presentSearch() },
                CPBarButton(title: "Mijn locatie") { [weak mapViewController] _ in mapViewController?.recenter() }
            ]
            interfaceController.setRootTemplate(mapTemplate, animated: false)

            CarPlayDrivingTaskCoordinator.shared.locationService = locationService
            CarPlayDrivingTaskCoordinator.shared.attach(interfaceController: interfaceController)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        Task { @MainActor in
            CarPlaySessionTracker.isForegroundOnCarPlay = false
            CarPlayDrivingTaskCoordinator.shared.detach()
            navigationSession?.cancelTrip()
            navigationSession = nil
            self.locationService?.stop()
            self.locationService = nil
            self.mapViewController = nil
            self.interfaceController = nil
            self.mapTemplate = nil
        }
    }

    private func presentSearch() {
        let template = CPSearchTemplate()
        template.delegate = self
        searchTemplate = template
        interfaceController?.pushTemplate(template, animated: true)
    }

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        updatedSearchText searchText: String,
        completionHandler: @escaping ([CPListItem]) -> Void
    ) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            completionHandler([])
            return
        }

        CLGeocoder().geocodeAddressString(query) { placemarks, _ in
            let items = (placemarks ?? []).prefix(5).compactMap { placemark -> CPListItem? in
                guard let coordinate = placemark.location?.coordinate else { return nil }
                let title = placemark.name ?? query
                let detail = [placemark.locality, placemark.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                let item = CPListItem(text: title, detailText: detail.isEmpty ? nil : detail)
                item.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        await self?.startRoute(to: coordinate, title: title)
                        completion()
                    }
                }
                return item
            }
            DispatchQueue.main.async { completionHandler(items) }
        }
    }

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        selectedResult selectedResultItem: CPListItem,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    private func startRoute(to coordinate: CLLocationCoordinate2D, title: String) async {
        guard let origin = mapViewController?.mapView.userLocation.location,
              let mapTemplate else { return }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return }

            mapViewController?.showRoute(route)
            let trip = CPTrip(
                origin: request.source!,
                destination: request.destination!,
                routeChoices: [
                    CPRouteChoice(
                        summaryVariants: [title],
                        additionalInformationVariants: [String(format: "%.0f min", route.expectedTravelTime / 60.0)],
                        selectionSummaryVariants: [title]
                    )
                ]
            )
            navigationSession = mapTemplate.startNavigationSession(for: trip)
            navigationSession?.pauseTrip(for: .loading, description: "Route wordt voorbereid")
            maneuvers = route.steps.filter { !$0.instructions.isEmpty }.map { step in
                let maneuver = CPManeuver()
                maneuver.instructionVariants = [step.instructions]
                maneuver.dashboardInstructionVariants = [step.instructions]
                maneuver.notificationInstructionVariants = [step.instructions]
                maneuver.maneuverType = .followRoad
                maneuver.initialTravelEstimates = CPTravelEstimates(
                    distanceRemaining: step.distance,
                    timeRemaining: step.expectedTravelTime
                )
                return maneuver
            }
            let tripEstimates = CPTravelEstimates(
                distanceRemaining: route.distance,
                timeRemaining: route.expectedTravelTime
            )
            let current = maneuvers.first.map { [$0] } ?? []
            let currentEstimate = maneuvers.first?.initialTravelEstimates ?? tripEstimates
            let info = CPRouteInformation(
                maneuvers: maneuvers,
                laneGuidances: [],
                currentManeuvers: current,
                currentLaneGuidance: CPLaneGuidance(),
                tripTravelEstimates: tripEstimates,
                maneuverTravelEstimates: currentEstimate
            )
            navigationSession?.resumeTrip(withUpdatedRouteInformation: info)
            interfaceController?.popTemplate(animated: true)
        } catch {
            mapViewController?.showNavigationError("Route berekenen mislukt")
        }
    }
}
