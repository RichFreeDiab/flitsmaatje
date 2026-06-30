import Foundation

enum FlitsMaatjeAPI {
    enum APIError: Error {
        case badURL
        case badResponse
    }

    static func fetchNearbyAlert(lat: Double, lng: Double, radiusKm: Double = AppConfig.pollRadiusKm) async throws -> NearbyAlert? {
        var components = URLComponents(url: AppConfig.apiBaseURL.appendingPathComponent("/api/nearby-alert"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "radius_km", value: String(radiusKm)),
        ]
        guard let url = components?.url else { throw APIError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse
        }
        let decoded = try JSONDecoder().decode(NearbyAlertResponse.self, from: data)
        return decoded.alert
    }
}
