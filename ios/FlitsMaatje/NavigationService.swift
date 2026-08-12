import AVFoundation
import CoreLocation
import Foundation
import MapKit

@MainActor
final class NavigationService: ObservableObject {
    @Published var searchQuery = ""
    @Published var searchResults: [MKMapItem] = []
    @Published var route: MKRoute?
    @Published var isNavigating = false
    @Published var isSearching = false
    @Published var currentStepIndex = 0
    @Published var statusMessage: String?
    @Published var distanceRemainingM = 0
    @Published var currentManeuverDistanceM = 0
    @Published var eta: Date?
    @Published var destinationName: String?
    @Published var laneSections: [LaneSection] = []
    @Published var laneGuidanceDistanceM: Int?
    @Published private(set) var trafficReports: [MapReport] = []
    @Published var voiceEnabled: Bool {
        didSet {
            speechDefaults.set(voiceEnabled, forKey: Self.speechPreferenceKey)
            AlertNotifier.setSpeechEnabled(voiceEnabled)
        }
    }
    @Published var reroutingEnabled = true
    @Published var finesEnabled = true
    @Published var alertsEnabled = true

    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenStep = -1
    private var lastSpokenDistanceBand = Int.max
    private var destinationCoordinate: CLLocationCoordinate2D?
    private var lastRerouteAt = Date.distantPast
    private var lastRouteCalculationAt = Date.distantPast
    private var isRerouting = false
    private var consecutiveOffRouteUpdates = 0

    private static let speechPreferenceKey = "spoken-guidance-enabled"
    private var speechDefaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    init() {
        let defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
        let enabled = defaults.object(forKey: Self.speechPreferenceKey) as? Bool ?? false
        voiceEnabled = enabled
        AlertNotifier.setSpeechEnabled(enabled)
    }

    func updateTrafficReports(_ reports: [MapReport]) {
        trafficReports = reports.filter { $0.type == "file" || $0.type == "ongeval" || $0.type == "wegwerkzaamheden" }
    }

    func setDestinationCoordinate(_ coordinate: CLLocationCoordinate2D) {
        destinationCoordinate = coordinate
    }

    func markRouteCalculatedNow() {
        lastRouteCalculationAt = Date()
    }

    var currentInstruction: String {
        guard let route, !route.steps.isEmpty else { return "Kies een bestemming" }
        guard currentStepIndex < route.steps.count else { return "Je bent aangekomen" }
        let text = route.steps[currentStepIndex].instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Volg de route" : text
    }

    func search(near coordinate: CLLocationCoordinate2D) async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 40_000,
            longitudinalMeters: 40_000
        )

        do {
            let response = try await runLocalSearch(request)
            searchResults = response.mapItems
        } catch {
            statusMessage = "Zoeken mislukt"
            searchResults = []
        }
    }

    func startNavigation(to destination: MKMapItem, from location: CLLocation) async {
        destinationCoordinate = destination.placemark.coordinate
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

        do {
            let response = try await calculateDirections(request)
            // Kies niet alleen de theoretisch snelste route: NDW-oponthoud
            // krijgt een concrete straf zodat een filevrije alternatiefroute
            // wordt gekozen wanneer die merkbaar sneller is.
            guard let best = response.routes.min(by: { routeScore($0) < routeScore($1) }) else {
                statusMessage = "Geen route gevonden"
                return
            }

            route = best
            laneGuidanceDistanceM = nil
            laneSections = (try? await FlitsMaatjeAPI.fetchLaneGuidance(
                origin: location.coordinate,
                destination: destination.placemark.coordinate
            )) ?? []
            currentStepIndex = 0
            lastSpokenStep = -1
            lastSpokenDistanceBand = Int.max
            isNavigating = true
            destinationName = destination.name ?? destination.placemark.title ?? "Bestemming"
            distanceRemainingM = Int(best.distance)
            currentManeuverDistanceM = Int(
                best.steps.first(where: {
                    !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                })?.distance ?? best.distance
            )
            eta = Date().addingTimeInterval(best.expectedTravelTime)
            lastRouteCalculationAt = Date()
            searchResults = []
            searchQuery = destinationName ?? ""
            statusMessage = "Navigatie gestart"
        } catch {
            statusMessage = "Route berekenen mislukt"
        }
    }

    func startNavigation(to coordinate: CLLocationCoordinate2D, name: String, from location: CLLocation) async {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        await startNavigation(to: item, from: location)
    }

    func stopNavigation() {
        route = nil
        isNavigating = false
        currentStepIndex = 0
        lastSpokenStep = -1
        lastSpokenDistanceBand = Int.max
        distanceRemainingM = 0
        currentManeuverDistanceM = 0
        eta = nil
        destinationName = nil
        laneSections = []
        laneGuidanceDistanceM = nil
        trafficReports = []
        destinationCoordinate = nil
        consecutiveOffRouteUpdates = 0
        lastRouteCalculationAt = .distantPast
        isRerouting = false
        statusMessage = "Navigatie gestopt"
        synthesizer.stopSpeaking(at: .immediate)
    }

    func updateProgress(location: CLLocation) {
        guard isNavigating, let route else { return }

        updateUpcomingLaneSections(from: location)

        let accuracyIsUsable = location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 50
        let deviationThreshold = max(30, location.horizontalAccuracy * 1.3)
        let routeDeviation = accuracyIsUsable ? distanceFromRoute(location, route: route) : 0
        if accuracyIsUsable && routeDeviation > deviationThreshold {
            consecutiveOffRouteUpdates += 1
        } else {
            consecutiveOffRouteUpdates = 0
        }

        let requiredOffRouteUpdates = location.horizontalAccuracy <= 20 ? 1 : 2
        if reroutingEnabled,
           let destinationCoordinate,
           consecutiveOffRouteUpdates >= requiredOffRouteUpdates,
           Date().timeIntervalSince(lastRerouteAt) > 3,
           !isRerouting {
            isRerouting = true
            consecutiveOffRouteUpdates = 0
            lastRerouteAt = Date()
            statusMessage = "Route herberekenen…"
            AppLogger.log("Herrouteren: \(Int(routeDeviation)) m van route")
            Task { @MainActor in
                await self.reroute(from: location, to: destinationCoordinate)
                self.isRerouting = false
            }
        }

        if reroutingEnabled,
           Date().timeIntervalSince(lastRerouteAt) > 60,
           !isRerouting,
           routeHasMeaningfulNDWDelay(route: route) {
            isRerouting = true
            lastRerouteAt = Date()
            Task { @MainActor in
                await self.reroute(from: location, to: self.destinationCoordinate ?? route.polyline.coordinates.last ?? location.coordinate)
                self.isRerouting = false
            }
        }

        if reroutingEnabled,
           let destinationCoordinate,
           Date().timeIntervalSince(lastRouteCalculationAt) > 120,
           !isRerouting {
            isRerouting = true
            lastRerouteAt = Date()
            Task { @MainActor in
                await self.reroute(from: location, to: destinationCoordinate)
                self.isRerouting = false
            }
        }

        advanceStepsIfNeeded(location: location, route: route)
        updateCurrentManeuverDistance(location: location, route: route)
        speakCurrentStepIfNeeded()

        let remaining = remainingDistance(on: route, from: location)
        distanceRemainingM = max(0, Int(remaining.rounded()))
        if remaining > 0, route.distance > 0, route.expectedTravelTime > 0 {
            let routeFraction = min(1, max(0, remaining / route.distance))
            eta = Date().addingTimeInterval(route.expectedTravelTime * routeFraction)
        }

        if currentStepIndex >= route.steps.count {
            statusMessage = "Bestemming bereikt"
            isNavigating = false
        }
    }

    private func distanceFromRoute(_ location: CLLocation, route: MKRoute) -> CLLocationDistance {
        let points = route.polyline.coordinates
        guard points.count >= 2 else {
            return points.first.map {
                location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            } ?? .greatestFiniteMagnitude
        }

        let userPoint = MKMapPoint(location.coordinate)
        var minimum = CLLocationDistance.greatestFiniteMagnitude
        for index in 0..<(points.count - 1) {
            let start = MKMapPoint(points[index])
            let end = MKMapPoint(points[index + 1])
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            let fraction: Double
            if lengthSquared == 0 {
                fraction = 0
            } else {
                fraction = min(1, max(0, ((userPoint.x - start.x) * dx + (userPoint.y - start.y) * dy) / lengthSquared))
            }
            let projected = MKMapPoint(x: start.x + fraction * dx, y: start.y + fraction * dy)
            minimum = min(minimum, userPoint.distance(to: projected))
        }
        return minimum
    }

    private func remainingDistance(on route: MKRoute, from location: CLLocation) -> CLLocationDistance {
        remainingDistance(on: route.polyline, from: location, fallback: route.distance)
    }

    private func remainingDistance(
        on polyline: MKPolyline,
        from location: CLLocation,
        fallback: CLLocationDistance
    ) -> CLLocationDistance {
        let points = polyline.coordinates.map { MKMapPoint($0) }
        guard points.count >= 2 else { return fallback }

        let userPoint = MKMapPoint(location.coordinate)
        var nearestSegment = 0
        var nearestFraction = 0.0
        var nearestDistance = CLLocationDistance.greatestFiniteMagnitude

        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            let fraction = lengthSquared == 0
                ? 0
                : min(1, max(0, ((userPoint.x - start.x) * dx + (userPoint.y - start.y) * dy) / lengthSquared))
            let projected = MKMapPoint(x: start.x + fraction * dx, y: start.y + fraction * dy)
            let distance = userPoint.distance(to: projected)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestSegment = index
                nearestFraction = fraction
            }
        }

        var remaining = points[nearestSegment].distance(to: points[nearestSegment + 1]) * (1 - nearestFraction)
        if nearestSegment + 1 < points.count - 1 {
            for index in (nearestSegment + 1)..<(points.count - 1) {
                remaining += points[index].distance(to: points[index + 1])
            }
        }
        return remaining
    }

    private func updateCurrentManeuverDistance(location: CLLocation, route: MKRoute) {
        guard currentStepIndex < route.steps.count else {
            currentManeuverDistanceM = 0
            return
        }
        let step = route.steps[currentStepIndex]
        let remaining = remainingDistance(
            on: step.polyline,
            from: location,
            fallback: step.distance
        )
        currentManeuverDistanceM = max(0, Int(remaining.rounded()))
    }

    private func reroute(from location: CLLocation, to destination: CLLocationCoordinate2D) async {
        let previousRoute = route
        let item = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        item.name = destinationName ?? "Bestemming"
        await startNavigation(to: item, from: location)
        if route !== previousRoute {
            statusMessage = "Route automatisch herberekend"
            AppLogger.log("Route automatisch herberekend")
        } else {
            statusMessage = "Herberekenen mislukt – oude route blijft actief"
            AppLogger.error("Herrouteren leverde geen nieuwe route op")
        }
    }

    private func updateUpcomingLaneSections(from location: CLLocation) {
        laneSections.removeAll { section in
            guard let coordinate = section.endCoordinate else { return false }
            let end = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            // Houd de pijlen zichtbaar tot de sectie daadwerkelijk achter de
            // auto ligt. Alleen afstand liet ze 60 meter vóór de afslag wegvallen.
            return location.distance(from: end) <= 90
                && isBehindVehicle(coordinate, from: location)
        }
        laneSections.sort { left, right in
            laneDistance(left, from: location) < laneDistance(right, from: location)
        }
        guard let section = laneSections.first else {
            laneGuidanceDistanceM = nil
            return
        }
        let distance = laneDistance(section, from: location)
        // Altijd volgende rijbaanvoorstel tonen tijdens navigatie (niet pas <2km).
        // Afstand blijft zichtbaar; UI toont lane-pijlen zolang er een sectie is.
        if distance.isFinite {
            laneGuidanceDistanceM = max(0, Int(distance.rounded()))
        } else {
            laneGuidanceDistanceM = nil
        }
    }

    private func laneDistance(_ section: LaneSection, from location: CLLocation) -> CLLocationDistance {
        guard let coordinate = section.startCoordinate else { return .greatestFiniteMagnitude }
        if isBehindVehicle(coordinate, from: location),
           let end = section.endCoordinate,
           !isBehindVehicle(end, from: location) {
            return 0
        }
        return location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    private func isBehindVehicle(
        _ coordinate: CLLocationCoordinate2D,
        from location: CLLocation
    ) -> Bool {
        guard location.course >= 0 else { return false }
        let lat1 = location.coordinate.latitude * .pi / 180
        let lat2 = coordinate.latitude * .pi / 180
        let longitudeDelta = (coordinate.longitude - location.coordinate.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(longitudeDelta)
        let bearing = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let delta = abs((bearing - location.course + 540).truncatingRemainder(dividingBy: 360) - 180)
        return delta > 105
    }

    private func routeScore(_ route: MKRoute) -> TimeInterval {
        route.expectedTravelTime + ndwPenalty(for: route)
    }

    private func ndwPenalty(for route: MKRoute) -> TimeInterval {
        let points = route.polyline.coordinates
        guard !points.isEmpty else { return 0 }
        return trafficReports.reduce(0) { total, report in
            let reportLocation = CLLocation(latitude: report.lat, longitude: report.lng)
            let nearRoute = points.contains {
                reportLocation.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= 180
            }
            guard nearRoute else { return total }
            switch report.type {
            case "ongeval": return total + 600
            case "wegwerkzaamheden": return total + 300
            default: return total + 240
            }
        }
    }

    private func routeHasMeaningfulNDWDelay(route: MKRoute) -> Bool {
        ndwPenalty(for: route) >= 240
    }

    private func advanceStepsIfNeeded(location: CLLocation, route: MKRoute) {
        while currentStepIndex < route.steps.count {
            let step = route.steps[currentStepIndex]
            if step.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentStepIndex += 1
                continue
            }
            guard let end = stepEndCoordinate(for: step) else {
                currentStepIndex += 1
                continue
            }
            let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
            if location.distance(from: endLocation) > 45 {
                break
            }
            currentStepIndex += 1
        }
    }

    private func stepEndCoordinate(for step: MKRoute.Step) -> CLLocationCoordinate2D? {
        guard step.polyline.pointCount > 0 else { return nil }
        return step.polyline.coordinates.last
    }

    private func speakCurrentStepIfNeeded() {
        guard voiceEnabled else { return }
        guard currentStepIndex < route?.steps.count ?? 0 else { return }
        let distanceBand: Int
        if currentManeuverDistanceM <= 80 {
            distanceBand = 0
        } else if currentManeuverDistanceM <= 300 {
            distanceBand = 1
        } else if currentManeuverDistanceM <= 800 {
            distanceBand = 2
        } else {
            distanceBand = 3
        }
        if currentStepIndex != lastSpokenStep {
            lastSpokenStep = currentStepIndex
            lastSpokenDistanceBand = 3
        }
        guard distanceBand < lastSpokenDistanceBand else { return }
        lastSpokenDistanceBand = distanceBand
        let text = currentInstruction
        guard !text.isEmpty, text != "Volg de route" else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "nl-NL")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func calculateDirections(_ request: MKDirections.Request) async throws -> MKDirections.Response {
        try await withCheckedThrowingContinuation { continuation in
            MKDirections(request: request).calculate { response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
        }
    }

    private func runLocalSearch(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
        try await withCheckedThrowingContinuation { continuation in
            MKLocalSearch(request: request).start { response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
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
