import Foundation

struct NearbyAlertResponse: Codable {
    let alert: NearbyAlert?
}

struct ReportsResponse: Codable {
    let reports: [MapReport]
}

struct MapReport: Codable, Equatable, Identifiable {
    let id: String
    let type: String
    let lat: Double
    let lng: Double
    let confirms: Int
    let distance_km: Double

    var label: String {
        switch type {
        case "flitser_vast": return "Vaste flitspaal"
        case "flitser_mobiel": return "Mobiele flitser"
        case "trajectcontrole": return "Trajectcontrole"
        case "file": return "File"
        case "ongeval": return "Ongeval"
        case "wegwerkzaamheden": return "Wegomleiding / werkzaamheden"
        case "gevaar": return "Gevaar op de weg"
        default: return "Verkeersmelding"
        }
    }

    var icon: String {
        switch type {
        case "flitser_vast": return "📷"
        case "trajectcontrole": return "📡"
        case "flitser_mobiel": return "🚐"
        case "file": return "🚗"
        case "ongeval": return "💥"
        case "wegwerkzaamheden": return "🚧"
        case "gevaar": return "⚠️"
        default: return "⚠️"
        }
    }
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
        displayText(speedKmh: nil, limit: nil)
    }

    func displayText(speedKmh: Int?, limit: Int?) -> String? {
        guard excess_kmh >= 4 else { return nil }
        if om_zaak {
            return "\(excess_kmh) km/u te hard na meetcorrectie — controleer OM Boetebase"
        }
        if let bedrag {
            return "\(excess_kmh) km/u te hard na meetcorrectie — indicatief €\(bedrag) incl. kosten"
        }
        return "\(excess_kmh) km/u te hard na meetcorrectie"
    }

    func carPlaySubtitle(speedKmh: Int?, limit: Int?) -> String {
        let speed = speedKmh.map { "\($0) km/u" } ?? "— km/u"
        let limitText = limit.map { "limiet \($0)" } ?? "limiet onbekend"
        return "\(speed) · \(limitText)"
    }

    func carPlayNotificationTitle(speedKmh: Int?, limit: Int?) -> String? {
        guard displayText(speedKmh: speedKmh, limit: limit) != nil else { return nil }
        return om_zaak ? "Te hard — controleer boete" : "Te hard — indicatief €\(bedrag ?? 0)"
    }

    func carPlayNotificationSubtitle(speedKmh: Int?, limit: Int?) -> String? {
        guard carPlayNotificationTitle(speedKmh: speedKmh, limit: limit) != nil else { return nil }
        return "\(carPlaySubtitle(speedKmh: speedKmh, limit: limit)) · \(excess_kmh) km/u na correctie"
    }
}

struct SpeedCheckResponse: Codable {
    let limit: SpeedLimitInfo
    let fine: FineEstimate?
}

struct WidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    var latitude: Double?
    var longitude: Double?
    var alert: NearbyAlert?
    var speedKmh: Int?
    var speedLimitKmh: Int?
    var fineText: String?
    var statusMessage: String

    static let clear = WidgetSnapshot(
        updatedAt: Date(),
        latitude: nil,
        longitude: nil,
        alert: nil,
        speedKmh: nil,
        speedLimitKmh: nil,
        fineText: nil,
        statusMessage: "Geen meldingen in de buurt"
    )
}
