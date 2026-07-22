import CarPlay
import CoreLocation
import MapKit
import UIKit

@MainActor
final class CarPlayNavigationCoordinator: NSObject {
    static let shared = CarPlayNavigationCoordinator()

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
        searchTemplate = nil
        lastFlitserAlertId = nil
    }

    func syncFromPhoneNavigation() {
        guard let route = navigationService?.route,
              let name = navigationService?.destinationName,
              let user = locationService?.lastLocation else { return }
        presentTripPreview(route: route, destinationName: name, from: user)
    }

    func handleFlitserAlert(_ alert: NearbyAlert?) {
        // Geen CPNavigationAlert: een modal boven Apple Kaarten veroorzaakt
        // overlap en kan de actieve CarPlay-navigatiesessie onderbreken.
        guard let alert else {
            lastFlitserAlertId = nil
            return
        }
        guard lastFlitserAlertId != alert.id else { return }
        lastFlitserAlertId = alert.id
        AppLogger.log("CarPlay flitserstatus: \(alert.label) op \(alert.distance_m)m")
    }

    func updateNavigationProgress() {
        guard let navigationService, let route = navigationService.route, navigationSession != nil else {
            return
        }

        if navigationService.currentStepIndex >= route.steps.count {
            endGuidance()
            return
        }

        updateManeuvers(for: route)
        if let trip = activeTrip {
            let estimates = CPTravelEstimates(
                distanceRemaining: Measurement(
                    value: Double(navigationService.distanceRemainingM),
                    unit: UnitLength.meters
                ),
                timeRemaining: navigationService.eta?.timeIntervalSinceNow ?? route.expectedTravelTime
            )
            mapTemplate?.updateEstimates(estimates, for: trip)
        }
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

        let home = CPMapButton { [weak self] _ in
            self?.startFavorite(.home)
        }
        home.image = UIImage(systemName: FavoriteDestinationKind.home.systemImage)

        let work = CPMapButton { [weak self] _ in
            self?.startFavorite(.work)
        }
        work.image = UIImage(systemName: FavoriteDestinationKind.work.systemImage)

        let pan = CPMapButton { [weak self] _ in
            self?.mapTemplate?.showPanningInterface(animated: true)
        }
        pan.image = UIImage(systemName: "hand.draw")
        template.mapButtons = [home, work, pan]
    }

    private func showSearch() {
        guard let interfaceController else { return }
        let template = CPSearchTemplate()
        template.delegate = self
        searchTemplate = template
        interfaceController.pushTemplate(template, animated: true)
    }

    private func startFavorite(_ kind: FavoriteDestinationKind) {
        guard let favorite = FavoriteDestinationStore.destination(for: kind) else {
            presentFavoriteSetupMessage(for: kind)
            return
        }
        Task { [weak self] in
            await self?.calculateAndPreview(to: favorite.mapItem)
        }
    }

    private func presentFavoriteSetupMessage(for kind: FavoriteDestinationKind) {
        let template = CPAlertTemplate(
            titleVariants: ["\(kind.title) is nog niet ingesteld"],
            actions: [CPAlertAction(title: "OK", style: .default) { _ in }]
        )
        interfaceController?.presentTemplate(template, animated: true)
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
        navigationService?.isNavigating = true
        updateManeuvers(for: route)

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

    private func updateManeuvers(for route: MKRoute) {
        guard let session = navigationSession else { return }
        let startIndex = navigationService?.currentStepIndex ?? 0
        let maneuvers: [CPManeuver] = route.steps.dropFirst(startIndex).prefix(3).compactMap { step in
            let text = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let maneuver = CPManeuver()
            maneuver.instructionVariants = [text]
            maneuver.dashboardInstructionVariants = [text]
            maneuver.notificationInstructionVariants = [text]
            maneuver.initialTravelEstimates = CPTravelEstimates(
                distanceRemaining: Measurement(value: step.distance, unit: UnitLength.meters),
                timeRemaining: max(1, step.distance / 13.9)
            )
            return maneuver
        }
        session.upcomingManeuvers = maneuvers
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
        guard let user = locationService?.lastLocation else {
            AppLogger.error("CarPlay route: geen GPS-positie")
            return
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: user.coordinate))
        request.destination = mapItem
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                AppLogger.error("CarPlay route: geen route")
                return
            }
            navigationService?.route = route
            navigationService?.currentStepIndex = 0
            navigationService?.isNavigating = false
            navigationService?.destinationName = mapItem.name ?? "Bestemming"
            navigationService?.distanceRemainingM = Int(route.distance)
            navigationService?.eta = Date().addingTimeInterval(route.expectedTravelTime)
            presentTripPreview(
                route: route,
                destinationName: mapItem.name ?? "Bestemming",
                from: user
            )
            try? await interfaceController?.popTemplate(animated: true)
        } catch {
            AppLogger.error("CarPlay route mislukt: \(error.localizedDescription)")
            let template = CPAlertTemplate(
                titleVariants: ["Route berekenen mislukt"],
                actions: [CPAlertAction(title: "OK", style: .default) { _ in }]
            )
            try? await interfaceController?.presentTemplate(template, animated: true)
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
                AppLogger.error("CarPlay zoeken mislukt: \(error.localizedDescription)")
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
