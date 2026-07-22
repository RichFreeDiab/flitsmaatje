import CoreLocation
import Foundation
import MapKit

enum FavoriteDestinationKind: String, CaseIterable {
    case home
    case work

    var title: String {
        switch self {
        case .home: return "Thuis"
        case .work: return "Werk"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "building.2.fill"
        }
    }
}

struct FavoriteDestination: Codable, Equatable {
    let title: String
    let address: String
    let latitude: Double
    let longitude: Double

    var mapItem: MKMapItem {
        let item = MKMapItem(
            placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            )
        )
        item.name = title
        return item
    }
}

enum FavoriteDestinationError: LocalizedError {
    case addressNotFound

    var errorDescription: String? {
        "Adres niet gevonden"
    }
}

enum FavoriteDestinationStore {
    private static let keyPrefix = "favorite-destination."

    static func destination(for kind: FavoriteDestinationKind) -> FavoriteDestination? {
        guard let data = UserDefaults.standard.data(forKey: keyPrefix + kind.rawValue) else {
            return nil
        }
        return try? JSONDecoder().decode(FavoriteDestination.self, from: data)
    }

    static func save(address: String, for kind: FavoriteDestinationKind) async throws {
        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw FavoriteDestinationError.addressNotFound }

        let placemarks = try await CLGeocoder().geocodeAddressString(query)
        guard let location = placemarks.first?.location else {
            throw FavoriteDestinationError.addressNotFound
        }

        let favorite = FavoriteDestination(
            title: kind.title,
            address: placemarks.first?.name ?? query,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        let data = try JSONEncoder().encode(favorite)
        UserDefaults.standard.set(data, forKey: keyPrefix + kind.rawValue)
    }
}
