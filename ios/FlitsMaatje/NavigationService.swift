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
    @Published var eta: Date?
    @Published var destinationName: String?
    @Published var voiceEnabled = true
    @Published var reroutingEnabled = true
    @Published var finesEnabled = true
    @Published var alertsEnabled = true

    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenStep = -1
    private var destinationCoordinate: CLLocationCoordinate2D?
    private var lastRerouteAt = Date.distantPast
    private var isRerouting = false

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

        do {
            let response = try await calculateDirections(request)
            guard let best = response.routes.first else {
                statusMessage = "Geen route gevonden"
                return
            }

            route = best
            currentStepIndex = 0
            lastSpokenStep = -1
            isNavigating = true
            destinationName = destination.name ?? destination.placemark.title ?? "Bestemming"
            distanceRemainingM = Int(best.distance)
            eta = Date().addingTimeInterval(best.expectedTravelTime)
            searchResults = []
            searchQuery = destinationName ?? ""
            statusMessage = "Navigatie gestart"
            speakCurrentStepIfNeeded()
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
        distanceRemainingM = 0
        eta = nil
        destinationName = nil
        destinationCoordinate = nil
        statusMessage = "Navigatie gestopt"
        synthesizer.stopSpeaking(at: .immediate)
    }

    func updateProgress(location: CLLocation) {
        guard isNavigating, let route else { return }

        if reroutingEnabled,
           let destinationCoordinate,
           distanceFromRoute(location, route: route) > 80,
           Date().timeIntervalSince(lastRerouteAt) > 10,
           !isRerouting {
            isRerouting = true
            lastRerouteAt = Date()
            Task { @MainActor in
                await self.reroute(from: location, to: destinationCoordinate)
                self.isRerouting = false
            }
        }

        advanceStepsIfNeeded(location: location, route: route)

        var remaining: CLLocationDistance = 0
        if currentStepIndex < route.steps.count {
            for index in currentStepIndex..<route.steps.count {
                remaining += route.steps[index].distance
            }
        }
        distanceRemainingM = max(0, Int(remaining))
        if remaining > 0, location.speed > 1 {
            eta = Date().addingTimeInterval(remaining / location.speed)
        }

        if currentStepIndex >= route.steps.count {
            statusMessage = "Bestemming bereikt"
            isNavigating = false
        }
    }

    private func distanceFromRoute(_ location: CLLocation, route: MKRoute) -> CLLocationDistance {
        let points = route.polyline.coordinates
        guard !points.isEmpty else { return .greatestFiniteMagnitude }
        return points.map {
            location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? .greatestFiniteMagnitude
    }

    private func reroute(from location: CLLocation, to destination: CLLocationCoordinate2D) async {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        item.name = destinationName ?? "Bestemming"
        await startNavigation(to: item, from: location)
        statusMessage = "Route automatisch herberekend"
    }

    private func advanceStepsIfNeeded(location: CLLocation, route: MKRoute) {
        while currentStepIndex < route.steps.count {
            let step = route.steps[currentStepIndex]
            guard let end = stepEndCoordinate(for: step) else {
                currentStepIndex += 1
                continue
            }
            let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
            if location.distance(from: endLocation) > 45 {
                break
            }
            currentStepIndex += 1
            speakCurrentStepIfNeeded()
        }
    }

    private func stepEndCoordinate(for step: MKRoute.Step) -> CLLocationCoordinate2D? {
        guard step.polyline.pointCount > 0 else { return nil }
        return step.polyline.coordinates.last
    }

    private func speakCurrentStepIfNeeded() {
        guard voiceEnabled, currentStepIndex != lastSpokenStep else { return }
        guard currentStepIndex < route?.steps.count ?? 0 else { return }
        lastSpokenStep = currentStepIndex
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
