import CoreLocation
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
    let road: String?
    let hectometer: String?

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
    let road: String?
    let hectometer: String?

    init(
        id: String,
        type: String,
        label: String,
        icon: String,
        distance_m: Int,
        lat: Double,
        lng: Double,
        confirms: Int,
        road: String? = nil,
        hectometer: String? = nil
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.icon = icon
        self.distance_m = distance_m
        self.lat = lat
        self.lng = lng
        self.confirms = confirms
        self.road = road
        self.hectometer = hectometer
    }
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

    var compactAmountText: String {
        guard excess_kmh >= 4 else { return "Boete —" }
        if om_zaak { return "Boete OM" }
        if let bedrag { return "Boete €\(bedrag)" }
        return "Boete --"
    }

    func displayText(speedKmh: Int?, limit: Int?) -> String? {
        guard excess_kmh >= 4 else { return nil }
        if om_zaak {
            return "Te hard: +\(excess_kmh) km/u · OM-tarief"
        }
        if let bedrag {
            return "Te hard: +\(excess_kmh) km/u · indicatief €\(bedrag)"
        }
        return "Te hard: +\(excess_kmh) km/u"
    }

    func carPlaySubtitle(speedKmh: Int?, limit: Int?) -> String {
        let speed = speedKmh.map { "\($0) km/u" } ?? "— km/u"
        let limitText = limit.map { "limiet \($0)" } ?? "limiet onbekend"
        return "\(speed) · \(limitText)"
    }

    func carPlayNotificationTitle(speedKmh: Int?, limit: Int?) -> String? {
        guard displayText(speedKmh: speedKmh, limit: limit) != nil else { return nil }
        return om_zaak ? "Te hard — controleer boete" : (bedrag.map { "Te hard — indicatief €\($0)" } ?? "Te hard — bedrag onbekend")
    }

    func carPlayNotificationSubtitle(speedKmh: Int?, limit: Int?) -> String? {
        guard carPlayNotificationTitle(speedKmh: speedKmh, limit: limit) != nil else { return nil }
        return carPlaySubtitle(speedKmh: speedKmh, limit: limit)
    }
}

enum FineCalculator {
    private static let administrationCost = 9
    private static let tables: [String: [Int: Int]] = [
        "bebouwde_kom": [
            4: 37, 5: 46, 6: 56, 7: 65, 8: 73, 9: 84, 10: 95,
            11: 129, 12: 140, 13: 155, 14: 166, 15: 179, 16: 192,
            17: 207, 18: 223, 19: 237, 20: 255, 21: 272, 22: 289,
            23: 308, 24: 324, 25: 345, 26: 363, 27: 387, 28: 405,
            29: 426, 30: 446,
        ],
        "buiten_bebouwde_kom": [
            4: 33, 5: 42, 6: 50, 7: 59, 8: 68, 9: 79, 10: 89,
            11: 121, 12: 134, 13: 147, 14: 159, 15: 172, 16: 184,
            17: 197, 18: 210, 19: 227, 20: 243, 21: 258, 22: 273,
            23: 289, 24: 308, 25: 326, 26: 345, 27: 362, 28: 381,
            29: 404, 30: 424,
        ],
        "snelweg": [
            4: 28, 5: 34, 6: 41, 7: 49, 8: 56, 9: 64, 10: 84,
            11: 115, 12: 126, 13: 136, 14: 147, 15: 159, 16: 171,
            17: 185, 18: 200, 19: 213, 20: 229, 21: 244, 22: 258,
            23: 273, 24: 289, 25: 304, 26: 321, 27: 337, 28: 350,
            29: 369, 30: 389, 31: 408, 32: 427, 33: 446, 34: 468,
            35: 488, 36: 508, 37: 524, 38: 524, 39: 524, 40: 541,
        ],
    ]

    static func estimate(zone: String?, measuredKmh: Int, limitKmh: Int) -> FineEstimate? {
        let resolvedZone: String
        if let zone, tables[zone] != nil {
            resolvedZone = zone
        } else if limitKmh >= 90 {
            resolvedZone = "snelweg"
        } else if limitKmh <= 50 {
            resolvedZone = "bebouwde_kom"
        } else {
            resolvedZone = "buiten_bebouwde_kom"
        }

        let corrected = measuredKmh <= 100
            ? Double(measuredKmh - 3)
            : Double(measuredKmh) * 0.97
        let excess = Int(floor(corrected - Double(limitKmh)))
        guard excess >= 4 else { return nil }

        guard let baseAmount = tables[resolvedZone]?[excess] else {
            return FineEstimate(
                excess_kmh: excess,
                bedrag: nil,
                bedrag_excl_administratiekosten: nil,
                om_zaak: true,
                indicatief: true
            )
        }
        return FineEstimate(
            excess_kmh: excess,
            bedrag: baseAmount + administrationCost,
            bedrag_excl_administratiekosten: baseAmount,
            om_zaak: false,
            indicatief: true
        )
    }
}

struct SpeedCheckResponse: Codable {
    let limit: SpeedLimitInfo
    let fine: FineEstimate?
    let traffic: TomTomTraffic?
}

struct LaneGuidanceResponse: Codable {
    let sections: [LaneSection]
}

struct LaneSection: Codable, Equatable {
    let start_point_index: Int
    let end_point_index: Int
    let start_lat: Double?
    let start_lng: Double?
    let end_lat: Double?
    let end_lng: Double?
    let lanes: [Lane]

    var startCoordinate: CLLocationCoordinate2D? {
        guard let start_lat, let start_lng else { return nil }
        return CLLocationCoordinate2D(latitude: start_lat, longitude: start_lng)
    }

    var endCoordinate: CLLocationCoordinate2D? {
        guard let end_lat, let end_lng else { return nil }
        return CLLocationCoordinate2D(latitude: end_lat, longitude: end_lng)
    }
}

struct Lane: Codable, Equatable {
    let directions: [String]
    let follow: String?
}

struct TomTomTraffic: Codable, Equatable {
    let current_speed_kmh: Int?
    let free_flow_speed_kmh: Int?
    let current_travel_time_s: Int?
    let free_flow_travel_time_s: Int?
    let delay_s: Int?
    let road_closure: Bool
    let confidence: Double?
    let source: String
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
