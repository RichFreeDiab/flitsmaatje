import Foundation

enum SharedStore {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppConfig.appGroupID)
    }

    static func load() -> WidgetSnapshot {
        guard
            let defaults,
            let data = defaults.data(forKey: AppConfig.sharedDefaultsKey),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else {
            return .clear
        }
        return snapshot
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: AppConfig.sharedDefaultsKey)
        }
    }
}
