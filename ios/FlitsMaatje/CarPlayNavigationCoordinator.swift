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
    private var laneGuidanceSignature: String?
    private var activeLaneGuidance: AnyObject?
    private var laneGuidanceLastSeenAt = Date.distantPast
    private var maneuverRouteIdentifier: ObjectIdentifier?
    private var maneuverStepIndex = -1
    private var stableManeuvers: [CPManeuver] = []

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
        laneGuidanceSignature = nil
        activeLaneGuidance = nil
        laneGuidanceLastSeenAt = .distantPast
        maneuverRouteIdentifier = nil
        maneuverStepIndex = -1
        stableManeuvers = []
    }

    func syncFromPhoneNavigation() {
        guard let route = navigationService?.route,
              let name = navigationService?.destinationName,
              let user = locationService?.lastLocation else { return }
        presentTripPreview(route: route, destinationName: name, from: user, autoStart: true)
    }

    func handleFlitserAlert(_ alert: NearbyAlert?) {
        guard let alert, navigationSession != nil else {
            lastFlitserAlertId = nil
            return
        }
        guard lastFlitserAlertId != alert.id else { return }
        lastFlitserAlertId = alert.id

        // Geen CPNavigationAlert: die gebruikt dezelfde bovenste ruimte als
        // de manoeuvrekaart. De compacte flitserkaart staat rechtsonder.
        refreshDrivingOverlay()
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
            distanceText: nil,
            laneSections: []
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
        mapViewController?.updateManeuver(instruction: navigationService?.currentInstruction, distanceText: nil, laneSections: [])

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

        let routeIdentifier = ObjectIdentifier(route)
        let mustRebuild = routeIdentifier != maneuverRouteIdentifier || startIndex != maneuverStepIndex
        if mustRebuild {
            stableManeuvers = route.steps
                .dropFirst(startIndex)
                .filter {
                    !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                .prefix(3)
                .enumerated()
                .compactMap { offset, step in
                    let instruction = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !instruction.isEmpty else { return nil }
                    let maneuver = CPManeuver()
                    let image = UIImage(systemName: maneuverSymbolName(for: instruction))?
                        .withTintColor(.white, renderingMode: .alwaysOriginal)
                    let variants = instructionVariants(for: instruction, isCurrent: offset == 0)
                    maneuver.symbolImage = image
                    maneuver.dashboardSymbolImage = image
                    maneuver.notificationSymbolImage = image
                    maneuver.instructionVariants = variants
                    maneuver.dashboardInstructionVariants = variants
                    maneuver.notificationInstructionVariants = variants
                    maneuver.cardBackgroundColor = .black
                    let distance = offset == 0
                        ? Double(navigationService?.currentManeuverDistanceM ?? Int(step.distance))
                        : step.distance
                    maneuver.initialTravelEstimates = CPTravelEstimates(
                        distanceRemaining: Measurement(value: max(0, distance), unit: UnitLength.meters),
                        timeRemaining: max(1, distance / 13.9)
                    )
                    return maneuver
                }
            maneuverRouteIdentifier = routeIdentifier
            maneuverStepIndex = startIndex
            // Alleen een nieuwe route of afslag vervangt de kaart. Bij gewone
            // GPS-updates blijft hetzelfde CPManeuver-object op zijn plek.
            session.upcomingManeuvers = stableManeuvers
        } else if let current = stableManeuvers.first {
            // Live bijwerken: baan + afrittekst op huidige manoeuvre
            let instruction = navigationService?.currentInstruction ?? ""
            let variants = instructionVariants(for: instruction, isCurrent: true)
            if current.instructionVariants != variants {
                current.instructionVariants = variants
                current.dashboardInstructionVariants = variants
                current.notificationInstructionVariants = variants
            }
            let symbol = maneuverSymbolName(for: instruction)
            if let image = UIImage(systemName: symbol)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                current.symbolImage = image
                current.dashboardSymbolImage = image
                current.notificationSymbolImage = image
            }
        }

        if let current = stableManeuvers.first {
            let distance = Double(max(0, navigationService?.currentManeuverDistanceM ?? 0))
            let estimates = CPTravelEstimates(
                distanceRemaining: Measurement(value: distance, unit: UnitLength.meters),
                timeRemaining: max(1, distance / 13.9)
            )
            session.updateEstimates(estimates, for: current)
        }

        if #available(iOS 17.4, *) {
            updateModernNavigationMetadata(session: session, maneuvers: stableManeuvers)
        }
    }

    private func maneuverSymbolName(for instruction: String) -> String {
        let text = instruction.lowercased()
        if text.contains("rotonde") || text.contains("roundabout") { return "arrow.clockwise" }
        if text.contains("keer") || text.contains("u-turn") { return "arrow.uturn.left" }
        if text.contains("afrit") || text.contains("exit") || text.contains("off ramp") {
            return "arrow.turn.up.right"
        }
        if text.contains("links") || text.contains("left") { return "arrow.turn.up.left" }
        if text.contains("rechts") || text.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }

    /// CarPlay-kaarttekst: baan + afritnaam (huidige stap), of afrit per stap.
    private func instructionVariants(for instruction: String, isCurrent: Bool) -> [String] {
        var parts: [String] = []
        if isCurrent, let lane = navigationService?.recommendedLaneText {
            parts.append(lane)
        }
        if let exit = NavigationService.parseExit(from: instruction),
           let exitText = NavigationService.formatExitBanner(exit) {
            parts.append(exitText)
        } else if isCurrent {
            let short = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !short.isEmpty, short != "Volg de route", short.count <= 60 {
                parts.append(short)
            }
        }
        if parts.isEmpty {
            // NBSP houdt CarPlay-kaart geldig als alleen het pijlsymbool telt
            return ["\u{00A0}"]
        }
        let primary = parts.joined(separator: " · ")
        return [primary, parts[0]]
    }

    @available(iOS 17.4, *)
    private func updateModernNavigationMetadata(
        session: CPNavigationSession,
        maneuvers: [CPManeuver]
    ) {
        let distance = navigationService?.currentManeuverDistanceM ?? 0
        if distance <= 80 {
            session.maneuverState = .execute
        } else if distance <= 800 {
            session.maneuverState = .prepare
        } else {
            session.maneuverState = .initial
        }

        if let roadName = locationService?.roadName, !roadName.isEmpty {
            session.currentRoadNameVariants = [roadName]
        } else {
            session.currentRoadNameVariants = []
        }

        guard navigationService?.laneGuidanceDistanceM != nil,
              let section = navigationService?.laneSections.first,
              !section.lanes.isEmpty else {
            // Een enkele onnauwkeurige GPS-update mag de rijstrookkaart niet
            // laten knipperen. Houd de laatste geldige aanwijzing kort vast.
            if Date().timeIntervalSince(laneGuidanceLastSeenAt) > 2.5 {
                session.currentLaneGuidance = nil
                laneGuidanceSignature = nil
                activeLaneGuidance = nil
            }
            return
        }

        laneGuidanceLastSeenAt = Date()
        let laneSignature = section.lanes
            .map { "\($0.directions.joined(separator: ",")):\($0.follow ?? "-")" }
            .joined(separator: "|")
        let textSignature = [
            navigationService?.recommendedLaneText ?? "",
            navigationService?.currentExitBannerText ?? "",
        ].joined(separator: "|")
        let signature = "\(section.start_point_index)-\(section.end_point_index):\(laneSignature):\(textSignature)"
        let guidance: CPLaneGuidance
        let createdNewGuidance: Bool
        if signature == laneGuidanceSignature,
           let cached = activeLaneGuidance as? CPLaneGuidance {
            guidance = cached
            createdNewGuidance = false
        } else {
            let newGuidance = CPLaneGuidance()
            newGuidance.instructionVariants = laneGuidanceInstructionVariants()
            newGuidance.lanes = section.lanes.compactMap(makeCarPlayLane)
            guard !newGuidance.lanes.isEmpty else {
                session.currentLaneGuidance = nil
                return
            }
            session.add([newGuidance])
            laneGuidanceSignature = signature
            activeLaneGuidance = newGuidance
            guidance = newGuidance
            createdNewGuidance = true
        }

        // Opnieuw toewijzen van hetzelfde object kan CarPlay animeren.
        if createdNewGuidance || session.currentLaneGuidance == nil {
            session.currentLaneGuidance = guidance
        }
        maneuvers.first?.linkedLaneGuidance = guidance
    }

    @available(iOS 17.4, *)
    private func laneGuidanceInstructionVariants() -> [String] {
        var parts: [String] = []
        if let lane = navigationService?.recommendedLaneText {
            parts.append(lane)
        }
        if let exit = navigationService?.currentExitBannerText {
            parts.append(exit)
        }
        if parts.isEmpty {
            return ["Kies de gemarkeerde rijstrook", "Rijstrook"]
        }
        let primary = parts.joined(separator: " · ")
        return [primary, parts[0]]
    }

    @available(iOS 17.4, *)
    private func makeCarPlayLane(_ lane: Lane) -> CPLane? {
        var directions = lane.directions
        if let follow = lane.follow, !directions.contains(follow) {
            directions.append(follow)
        }
        let angles = directions.compactMap(laneAngle)
        guard !angles.isEmpty else { return nil }
        let highlighted = lane.follow.flatMap(laneAngle)

        if #available(iOS 18.0, *) {
            if let highlighted {
                return CPLane(
                    angles: angles,
                    highlightedAngle: highlighted,
                    isPreferred: true
                )
            }
            return CPLane(angles: angles)
        }

        // De nieuwe immutable CPLane-initializers zijn pas vanaf iOS 18
        // beschikbaar. iOS 17.4 gebruikt de oudere, nog ondersteunde
        // properties zodat lane guidance ook daar zichtbaar blijft.
        let compatibleLane = CPLane()
        let primary = highlighted ?? angles[0]
        compatibleLane.primaryAngle = primary
        compatibleLane.secondaryAngles = angles.filter { $0 != primary }
        compatibleLane.status = highlighted == nil ? .notGood : .preferred
        return compatibleLane
    }

    private func laneAngle(_ direction: String) -> Measurement<UnitAngle>? {
        let degrees: Double
        switch direction.uppercased() {
        case "SHARP_LEFT": degrees = -135
        case "LEFT": degrees = -90
        case "SLIGHT_LEFT": degrees = -45
        case "STRAIGHT": degrees = 0
        case "SLIGHT_RIGHT": degrees = 45
        case "RIGHT": degrees = 90
        case "SHARP_RIGHT": degrees = 135
        case "LEFT_U_TURN": degrees = -180
        case "RIGHT_U_TURN": degrees = 180
        default: return nil
        }
        return Measurement(value: degrees, unit: UnitAngle.degrees)
    }

    func handleSpeedingFine(fine: FineEstimate?, speedKmh: Int?, limit: Int?) {
        guard navigationSession != nil,
              let fine,
              let title = fine.carPlayNotificationTitle(speedKmh: speedKmh, limit: limit)
        else {
            lastFineAlertText = nil
            refreshDrivingOverlay()
            return
        }
        let subtitle = fine.carPlayNotificationSubtitle(speedKmh: speedKmh, limit: limit) ?? ""
        let signature = "\(title)|\(subtitle)"
        guard signature != lastFineAlertText else { return }
        lastFineAlertText = signature
        // De persistente compacte boetekaart wordt rechtsonder getoond.
        // Vermijd een modal alert en navigatiebalkknop die de route bedekken.
        refreshDrivingOverlay()
        AppLogger.log("CarPlay boetemelding: \(title) — \(subtitle)")
    }

    private func refreshDrivingOverlay() {
        guard let locationService else { return }
        let alertText = locationService.currentAlert.map {
            "\($0.icon) \($0.label) • over \($0.distance_m) m"
        }
        mapViewController?.update(
            speedKmh: locationService.currentSpeedKmh,
            limit: locationService.speedLimit,
            alert: alertText,
            fineText: locationService.fineStatusText
        )
    }

    private func endGuidance() {
        navigationSession?.finishTrip()
        navigationSession = nil
        activeTrip = nil
        activeRoute = nil
        laneGuidanceSignature = nil
        activeLaneGuidance = nil
        laneGuidanceLastSeenAt = .distantPast
        maneuverRouteIdentifier = nil
        maneuverStepIndex = -1
        stableManeuvers = []
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
            navigationService?.laneGuidanceDistanceM = nil
            navigationService?.setDestinationCoordinate(mapItem.placemark.coordinate)
            navigationService?.currentStepIndex = 0
            navigationService?.isNavigating = false
            navigationService?.destinationName = mapItem.name ?? "Bestemming"
            navigationService?.distanceRemainingM = Int(route.distance)
            navigationService?.currentManeuverDistanceM = Int(
                route.steps.first(where: {
                    !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                })?.distance ?? route.distance
            )
            navigationService?.eta = Date().addingTimeInterval(route.expectedTravelTime)
            navigationService?.markRouteCalculatedNow()
            presentTripPreview(
                route: route,
                destinationName: mapItem.name ?? "Bestemming",
                from: user
            )
            mapViewController?.updateManeuver(
                instruction: navigationService?.currentInstruction,
                distanceText: String(format: "%.1f km", route.distance / 1000),
                laneSections: []
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
