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

struct SpeedLimitInfo: Codable, Equatable {
    let maxspeed: Int?
    let zone: String?
    let road_name: String?
    let source: String?
}

struct FineEstimate: Codable, Equatable {
    let excess_kmh: Int
    let bedrag: Int?
    let bedrag_excl_administratiekosten: Int?
    let om_zaak: Bool
    let indicatief: Bool?

    var displayText: String? {
        guard excess_kmh >= 4 else { return nil }
        if om_zaak {
            return "\(excess_kmh) km/u te hard — geen vaste boete, mogelijk OM-zaak (dagvaarding)"
        }
        if let bedrag {
            return "\(excess_kmh) km/u te hard — indicatief €\(bedrag) (incl. adm.kosten)"
        }
        return "\(excess_kmh) km/u te hard"
    }

    func displayText(speedKmh: Int?, limit: Int?) -> String? {
        let liveExcess: Int
        if let speedKmh, let limit {
            liveExcess = speedKmh - limit
        } else {
            liveExcess = excess_kmh
        }
        guard liveExcess >= 4 else { return nil }

        if om_zaak {
            return "\(liveExcess) km/u te hard — geen vaste boete, mogelijk OM-zaak (dagvaarding)"
        }
        if let bedrag {
            return "\(liveExcess) km/u te hard — indicatief €\(bedrag) (incl. adm.kosten)"
        }
        return "\(liveExcess) km/u te hard"
    }

    func carPlaySubtitle(speedKmh: Int?, limit: Int?) -> String {
        let speed = speedKmh.map { "\($0) km/u" } ?? "— km/u"
        let limitText = limit.map { "limiet \($0)" } ?? "limiet onbekend"
        return "\(speed) · \(limitText)"
    }
}

struct SpeedCheckResponse: Codable {
    let limit: SpeedLimitInfo
    let fine: FineEstimate?
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
