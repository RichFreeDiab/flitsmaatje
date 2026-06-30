import SwiftUI
import WidgetKit

struct FlitsMaatjeWidget: Widget {
    static let kind = "FlitsMaatjeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FlitsMaatjeProvider()) { entry in
            FlitsMaatjeWidgetView(entry: entry)
        }
        .configurationDisplayName("FlitsMaatje")
        .description("Toont de dichtstbijzijnde flitser of verkeersmelding — ook op CarPlay Dashboard.")
        .supportedFamilies([.systemSmall])
    }
}

struct FlitsMaatjeProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlitsMaatjeEntry {
        FlitsMaatjeEntry(
            date: Date(),
            snapshot: WidgetSnapshot(
                updatedAt: Date(),
                latitude: 52.37,
                longitude: 4.89,
                alert: NearbyAlert(
                    id: "demo",
                    type: "flitser_vast",
                    label: "Vaste flitser",
                    icon: "📷",
                    distance_m: 420,
                    lat: 52.37,
                    lng: 4.89,
                    confirms: 3
                ),
                statusMessage: "Vaste flitser over 420 m"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FlitsMaatjeEntry) -> Void) {
        completion(FlitsMaatjeEntry(date: Date(), snapshot: SharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlitsMaatjeEntry>) -> Void) {
        let snapshot = SharedStore.load()
        let entry = FlitsMaatjeEntry(date: Date(), snapshot: snapshot)
        // Backup refresh; echte updates komen van de app via reloadTimelines
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct FlitsMaatjeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct FlitsMaatjeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FlitsMaatjeEntry

    var body: some View {
        Group {
            if let alert = entry.snapshot.alert {
                alertView(alert)
            } else {
                clearView
            }
        }
        .containerBackground(for: .widget) {
            if entry.snapshot.alert != nil {
                LinearGradient(
                    colors: [Color.red.opacity(0.35), Color.black.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.black.opacity(0.85)
            }
        }
    }

    private func alertView(_ alert: NearbyAlert) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(alert.icon).font(.title2)
                Spacer()
                Text("FlitsMaatje")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(alert.label)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text("\(alert.distance_m) m")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var clearView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Spacer()
                Text("FlitsMaatje")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text("Geen meldingen")
                .font(.headline)
            Spacer(minLength: 0)
            Text(entry.snapshot.statusMessage)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview(as: .systemSmall) {
    FlitsMaatjeWidget()
} timeline: {
    FlitsMaatjeEntry(
        date: Date(),
        snapshot: WidgetSnapshot(
            updatedAt: Date(),
            latitude: nil,
            longitude: nil,
            alert: NearbyAlert(
                id: "1",
                type: "flitser_mobiel",
                label: "Mobiele flitser",
                icon: "🚐",
                distance_m: 650,
                lat: 0,
                lng: 0,
                confirms: 2
            ),
            statusMessage: "Mobiele flitser over 650 m"
        )
    )
}
