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
    private var lastFineAlertText: String?
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
        lastFineAlertText = nil
    }

    func syncFromPhoneNavigation() {
        guard let route = navigationService?.route,
              let name = navigationService?.destinationName,
              let user = locationService?.lastLocation else { return }
        presentTripPreview(route: route, destinationName: name, from: user, autoStart: true)
    }

    func handleFlitserAlert(_ alert: NearbyAlert?) {
        guard let alert, let mapTemplate, navigationSession != nil else {
            lastFlitserAlertId = nil
            return
        }
        guard lastFlitserAlertId != alert.id else { return }
        lastFlitserAlertId = alert.id

        // Alleen in de eigen actieve navigatiesessie: zo krijgt de bestuurder
        // een tijdige CarPlay-waarschuwing zonder Apple Kaarten te overlappen.
        let warning = CPNavigationAlert(
            titleVariants: ["\(alert.icon) \(alert.label)"],
            subtitleVariants: ["Over \(alert.distance_m) meter"],
            imageSet: nil,
            primaryAction: CPAlertAction(title: "OK", style: .default) { _ in },
            secondaryAction: nil,
            duration: 8
        )
        mapTemplate.present(navigationAlert: warning, animated: true)
        AppLogger.log("CarPlay flitserwaarschuwing: \(alert.label) op \(alert.distance_m)m")
    }

    func updateNavigationProgress() {
        guard let navigationService, let route = navigationService.route, navigationSession != nil else {
            return
        }

        if activeRoute !== route {
            activeRoute = route
            mapViewController?.showRoute(route)
            AppLogger.log("CarPlay-kaart bijgewerkt met herberekende route")
        }

        if navigationService.currentStepIndex >= route.steps.count {
            endGuidance()
            return
        }

        updateManeuvers(for: route)
        mapViewController?.updateManeuver(
            instruction: navigationService.currentInstruction,
            distanceText: navigationService.distanceRemainingM > 0 ? String(format: "%.1f km", Double(navigationService.distanceRemainingM) / 1000) : nil,
            laneSections: navigationService.laneSections
        )
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

    private func presentTripPreview(route: MKRoute, destinationName: String, from location: CLLocation, autoStart: Bool = false) {
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
        mapViewController?.updateManeuver(instruction: navigationService?.currentInstruction, distanceText: nil, laneSections: navigationService?.laneSections ?? [])

        let config = CPTripPreviewTextConfiguration(
            startButtonTitle: "Start",
            additionalRoutesButtonTitle: nil,
            overviewButtonTitle: "Overzicht"
        )
        mapTemplate.showTripPreviews([trip], textConfiguration: config)
        if autoStart {
            // Een bestaande telefoonroute is al door de gebruiker gekozen;
            // start CarPlay direct zodat er geen tweede keuze ontstaat.
            startGuidance(for: trip)
        }
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
        let lane = navigationService?.laneSections.first?.lanes.first
        let symbolName: String = {
            let direction = lane?.follow ?? lane?.directions.first ?? ""
            switch direction {
            case "LEFT", "SLIGHT_LEFT", "SHARP_LEFT": return "arrow.up.left"
            case "RIGHT", "SLIGHT_RIGHT", "SHARP_RIGHT": return "arrow.up.right"
            case "LEFT_U_TURN", "RIGHT_U_TURN": return "arrow.uturn.left"
            default: return "arrow.up"
            }
        }()

        let maneuvers: [CPManeuver] = route.steps
            .dropFirst(startIndex)
            .prefix(3)
            .compactMap { step in
                let instruction = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instruction.isEmpty else { return nil }
                let maneuver = CPManeuver()
                // Gebruik de echte korte manoeuvretekst zodat CarPlay zijn normale
                // donkere navigatiekaart rendert in plaats van de rode fallback.
                let image = UIImage(systemName: symbolName)
                maneuver.symbolImage = image
                maneuver.instructionVariants = [instruction]
                maneuver.dashboardInstructionVariants = [instruction]
                maneuver.notificationInstructionVariants = [instruction]
                maneuver.initialTravelEstimates = CPTravelEstimates(
                    distanceRemaining: Measurement(value: step.distance, unit: UnitLength.meters),
                    timeRemaining: max(1, step.distance / 13.9)
                )
                return maneuver
            }
        session.upcomingManeuvers = maneuvers
    }

    func handleSpeedingFine(fine: FineEstimate?, speedKmh: Int?, limit: Int?) {
        guard let mapTemplate, navigationSession != nil,
              let fine,
              let title = fine.carPlayNotificationTitle(speedKmh: speedKmh, limit: limit)
        else {
            lastFineAlertText = nil
            clearFineButton()
            return
        }
        let subtitle = fine.carPlayNotificationSubtitle(speedKmh: speedKmh, limit: limit) ?? ""
        let signature = "\(title)|\(subtitle)"
        guard signature != lastFineAlertText else { return }
        lastFineAlertText = signature
        showFineButton(title: title, subtitle: subtitle)

        let warning = CPNavigationAlert(
            titleVariants: ["⚠️ \(title)"],
            subtitleVariants: [subtitle],
            imageSet: nil,
            primaryAction: CPAlertAction(title: "OK", style: .default) { _ in },
            secondaryAction: nil,
            duration: 8
        )
        mapTemplate.present(navigationAlert: warning, animated: true)
        AppLogger.log("CarPlay boetemelding: \(title) — \(subtitle)")
    }

    private func showFineButton(title: String, subtitle: String) {
        guard let mapTemplate else { return }
        let buttonTitle = fineButtonTitle(from: title)
        let button = CPBarButton(title: buttonTitle) { [weak self] _ in
            let detail = CPAlertTemplate(
                titleVariants: [title],
                actions: [CPAlertAction(title: "OK", style: .default) { _ in }]
            )
            self?.interfaceController?.presentTemplate(detail, animated: true)
        }
        // De stopknop blijft links; de boete-indicatie blijft rechts permanent
        // zichtbaar zolang deze snelheidsovertreding actief is.
        mapTemplate.trailingNavigationBarButtons = [button]
        AppLogger.log("CarPlay boeteknop zichtbaar: \(buttonTitle)")
    }

    private func clearFineButton() {
        guard let mapTemplate, navigationSession != nil else { return }
        mapTemplate.trailingNavigationBarButtons = []
    }

    private func fineButtonTitle(from title: String) -> String {
        if let euroStart = title.range(of: "€") {
            let amount = title[euroStart.lowerBound...]
            return String(amount.prefix(8))
        }
        return "Boete"
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
        request.requestsAlternateRoutes = true

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
                AppLogger.error("CarPlay route: geen route")
                return
            }
            let laneSections = (try? await FlitsMaatjeAPI.fetchLaneGuidance(
                origin: user.coordinate,
                destination: mapItem.placemark.coordinate
            )) ?? []
            navigationService?.route = route
            navigationService?.laneSections = laneSections
            navigationService?.setDestinationCoordinate(mapItem.placemark.coordinate)
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
            mapViewController?.updateManeuver(
                instruction: navigationService?.currentInstruction,
                distanceText: String(format: "%.1f km", route.distance / 1000),
                laneSections: laneSections
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
