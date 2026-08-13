import Foundation
import CoreLocation

enum FlitsMaatjeAPI {
    enum APIError: Error {
        case badURL
        case badResponse
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func fetchNearbyAlert(
        lat: Double,
        lng: Double,
        heading: CLLocationDirection? = nil,
        road: String? = nil,
        radiusKm: Double = AppConfig.pollRadiusKm
    ) async throws -> NearbyAlert? {
        var components = URLComponents(url: AppConfig.apiBaseURL.appendingPathComponent("/api/nearby-alert"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "radius_km", value: String(radiusKm)),
        ]
        if let heading { components?.queryItems?.append(URLQueryItem(name: "heading", value: String(format: "%.1f", heading))) }
        if let road, !road.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "road", value: road))
        }
        guard let url = components?.url else { throw APIError.badURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse
        }
        let decoded = try JSONDecoder().decode(NearbyAlertResponse.self, from: data)
        return decoded.alert
    }

    static func fetchReports(lat: Double, lng: Double, radiusKm: Double = AppConfig.pollRadiusKm) async throws -> [MapReport] {
        var components = URLComponents(url: AppConfig.apiBaseURL.appendingPathComponent("/api/reports"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "radius_km", value: String(radiusKm)),
        ]
        guard let url = components?.url else { throw APIError.badURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse
        }
        return try JSONDecoder().decode(ReportsResponse.self, from: data).reports
    }

    static func fetchSpeedCheck(lat: Double, lng: Double, speedKmh: Double?) async throws -> SpeedCheckResponse {
        var components = URLComponents(url: AppConfig.apiBaseURL.appendingPathComponent("/api/speed-check"), resolvingAgainstBaseURL: false)
        var query = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
        ]
        if let speedKmh {
            query.append(URLQueryItem(name: "speed_kmh", value: String(format: "%.1f", speedKmh)))
        }
        components?.queryItems = query
        guard let url = components?.url else { throw APIError.badURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse
        }
        return try JSONDecoder().decode(SpeedCheckResponse.self, from: data)
    }

    static func fetchLaneGuidance(origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) async throws -> [LaneSection] {
        var components = URLComponents(url: AppConfig.apiBaseURL.appendingPathComponent("/api/lane-guidance"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "origin_lat", value: String(origin.latitude)),
            URLQueryItem(name: "origin_lng", value: String(origin.longitude)),
            URLQueryItem(name: "destination_lat", value: String(destination.latitude)),
            URLQueryItem(name: "destination_lng", value: String(destination.longitude)),
        ]
        guard let url = components?.url else { throw APIError.badURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.badResponse }
        return try JSONDecoder().decode(LaneGuidanceResponse.self, from: data).sections
    }
}
