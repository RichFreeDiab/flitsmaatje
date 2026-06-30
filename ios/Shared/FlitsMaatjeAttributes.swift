import ActivityKit
import Foundation

struct FlitsMaatjeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var reportType: String
        var label: String
        var distanceMeters: Int
        var icon: String
    }

    var startedAt: Date
}
