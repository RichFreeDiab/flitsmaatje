import Foundation

struct NearbyAlertResponse: Codable {
    let alert: NearbyAlert?
}

struct NearbyAlert: Codable, Equatable {
    let id: String
    let type: String
    let label: String
    let icon: String
    let distance_m: Int
    let lat: Double
    let lng: Double
    let confirms: Int
}

/// Snapshot gedeeld tussen app, widget en Live Activity via App Group.
struct WidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    var latitude: Double?
    var longitude: Double?
    var alert: NearbyAlert?
    var statusMessage: String

    static let clear = WidgetSnapshot(
        updatedAt: Date(),
        latitude: nil,
        longitude: nil,
        alert: nil,
        statusMessage: "Geen meldingen in de buurt"
    )
}
