import CarPlay
import CoreLocation
import MapKit
import UIKit

@MainActor
final class CarPlayNavigationCoordinator: NSObject {
    static var shared = CarPlayNavigationCoordinator()

    weak var locationService: LocationBackgroundService?
    weak var navigationService: NavigationService?

    private(set) var interfaceController: CPInterfaceController?
    private(set) var mapTemplate: CPMapTemplate?
    private weak var mapViewController: CarPlayMapViewController?
    private var navigationSession: CPNavigationSession?
    private var activeTrip: CPTrip?
    private var activeRoute: MKRoute?
    private var lastFlitserAlertId: String?
    private var searchTemplate: CPSearchTemplate?

    func attach(
        template: CPMapTemplate,
        mapViewController: CarPlayMapViewController,
        interfaceController: CPInterfaceController
    ) {
        self.mapTemplate = template
        self.mapViewController = mapViewController
        self.interfaceController = interfaceController
        template.mapDelegate = self
        configureDefaultButtons(on: template)
        syncFromPhoneNavigation()
    }

    func detach() {
        navigationSession?.finishTrip()
        navigationSession = nil
        activeTrip = nil
        activeRoute = nil
        mapTemplate = nil
        mapViewController = nil
        interfaceController = nil
    }

    func syncFromPhoneNavigation() {
        guard let route = navigationService?.route,
              let name = navigationService?.destinationName,
              let user = locationService?.lastLocation else { return }
        presentTripPreview(route: route, destinationName: name, from: user)
    }

    func handleFlitserAlert(_ alert: NearbyAlert?) {
        guard let alert, let mapTemplate else { return }
        guard lastFlitserAlertId != alert.id else { return }
        lastFlitserAlertId = alert.id

        let navAlert = CPNavigationAlert(
            titleVariants: ["\(alert.icon) \(alert.label)"],
            subtitleVariants: ["Over \(alert.distance_m) meter"],
            imageSet: nil,
            primaryAction: CPAlertAction(title: "OK", style: .default) { _ in },
            secondaryAction: nil,
            duration: 10
        )
        mapTemplate.present(navigationAlert: navAlert, animated: true)
    }

    func clearFlitserAlertState() {
        lastFlitserAlertId = nil
    }

    private func configureDefaultButtons(on template: CPMapTemplate) {
        let search = CPBarButton(title: "Zoek") { [weak self] _ in
            self?.showSearch()
        }
        let recenter = CPBarButton(title: "Centreren") { [weak self] _ in
            self?.mapViewController?.recenter()
        }
        template.leadingNavigationBarButtons = [search]
        template.trailingNavigationBarButtons = [recenter]

        let pan = CPMapButton { [weak self] _ in
            guard let template = self?.mapTemplate else { return }
            template.showPanningInterface(animated: true)
        }
        pan.image = UIImage(systemName: "hand.draw")
        template.mapButtons = [pan]
    }

    private func showSearch() {
        guard let interfaceController else { return }
        let template = CPSearchTemplate()
        template.delegate = self
        searchTemplate = template
        interfaceController.pushTemplate(template, animated: true)
    }

    private func presentTripPreview(route: MKRoute, destinationName: String, from location: CLLocation) {
        guard let mapTemplate else { return }

        let origin = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        origin.name = "Huidige locatie"
        let destCoord = route.polyline.coordinates.last ?? location.coordinate
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        destination.name = destinationName

        let minutes = Int(route.expectedTravelTime / 60)
        let distanceKm = String(format: "%.1f km", route.distance / 1000)
        let choice = CPRouteChoice(
            summaryVariants: [distanceKm],
            additionalInformationVariants: ["\(minutes) min"],
            selectionSummaryVariants: ["\(minutes) min · \(distanceKm)"]
        )

        let trip = CPTrip(origin: origin, destination: destination, routeChoices: [choice])
        activeRoute = route
        activeTrip = trip
        mapViewController?.showRoute(route)

        let config = CPTripPreviewTextConfiguration(
            startButtonTitle: "Start",
            additionalRoutesButtonTitle: nil,
            overviewButtonTitle: "Overzicht"
        )
        mapTemplate.showTripPreviews([trip], textConfiguration: config)
    }

    private func startGuidance(for trip: CPTrip) {
        guard let mapTemplate, let route = activeRoute else { return }

        mapTemplate.hideTripPreviews()
        navigationSession = mapTemplate.startNavigationSession(for: trip)
        mapViewController?.showRoute(route)
        updateManeuvers(for: route)

        navigationService?.isNavigating = true

        let estimates = CPTravelEstimates(
            distanceRemaining: Measurement(value: Double(route.distance), unit: UnitLength.meters),
            timeRemaining: route.expectedTravelTime
        )
        mapTemplate.updateEstimates(estimates, for: trip)

        let stop = CPBarButton(title: "Stop") { [weak self] _ in
            self?.endGuidance()
        }
        mapTemplate.leadingNavigationBarButtons = [stop]
        mapTemplate.trailingNavigationBarButtons = []
    }

    func updateNavigationProgress() {
        guard let route = navigationService?.route, navigationSession != nil else { return }
        updateManeuvers(for: route)
    }

    private func updateManeuvers(for route: MKRoute) {
        guard let session = navigationSession else { return }
        let startIndex = navigationService?.currentStepIndex ?? 0
        let maneuvers: [CPManeuver] = route.steps.dropFirst(startIndex).prefix(3).compactMap { step in
            let text = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let maneuver = CPManeuver()
            maneuver.instructionVariants = [text]
            let estimates = CPTravelEstimates(
                distanceRemaining: Measurement(value: step.distance, unit: UnitLength.meters),
                timeRemaining: 0
            )
            maneuver.initialTravelEstimates = estimates
            return maneuver
        }
        if !maneuvers.isEmpty {
            session.upcomingManeuvers = maneuvers
        }
    }

    private func endGuidance() {
        navigationSession?.finishTrip()
        navigationSession = nil
        activeTrip = nil
        activeRoute = nil
        navigationService?.stopNavigation()
        mapViewController?.clearRoute()
        mapTemplate?.hideTripPreviews()
        if let mapTemplate {
            configureDefaultButtons(on: mapTemplate)
        }
    }

    private func calculateAndPreview(to mapItem: MKMapItem) async {
        guard let user = locationService?.lastLocation, let mapTemplate else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: user.coordinate))
        request.destination = mapItem
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return }
            navigationService?.route = route
            navigationService?.isNavigating = false
            navigationService?.destinationName = mapItem.name ?? "Bestemming"
            presentTripPreview(
                route: route,
                destinationName: mapItem.name ?? "Bestemming",
                from: user
            )
            try? await interfaceController?.popTemplate(animated: true)
        } catch {
            // negeer — zoek blijft open
        }
    }
}

extension CarPlayNavigationCoordinator: CPMapTemplateDelegate {
    func mapTemplate(_ mapTemplate: CPMapTemplate, startedTrip trip: CPTrip, using routeChoice: CPRouteChoice) {
        startGuidance(for: trip)
    }

    func mapTemplateDidCancelNavigation(_ mapTemplate: CPMapTemplate) {
        endGuidance()
    }
}

extension CarPlayNavigationCoordinator: CPSearchTemplateDelegate {
    nonisolated func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        updatedSearchText searchText: String,
        completionHandler: @escaping ([CPListItem]) -> Void
    ) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            completionHandler([])
            return
        }

        Task { @MainActor in
            guard let user = self.locationService?.lastLocation else {
                completionHandler([])
                return
            }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            request.region = MKCoordinateRegion(
                center: user.coordinate,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
            do {
                let response = try await MKLocalSearch(request: request).start()
                let items = response.mapItems.prefix(8).map { item -> CPListItem in
                    let listItem = CPListItem(
                        text: item.name ?? "Locatie",
                        detailText: item.placemark.title
                    )
                    listItem.userInfo = item
                    return listItem
                }
                completionHandler(items)
            } catch {
                completionHandler([])
            }
        }
    }

    nonisolated func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        selectedResult item: CPListItem,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            if let mapItem = item.userInfo as? MKMapItem {
                await self.calculateAndPreview(to: mapItem)
            }
            completionHandler()
        }
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
