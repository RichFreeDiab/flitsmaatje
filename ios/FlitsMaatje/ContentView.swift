import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var location: LocationBackgroundService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    speedPanel
                    if let fineText = location.fineEstimate?.displayText(
                        speedKmh: location.currentSpeedKmh,
                        limit: location.speedLimit
                    ) {
                        fineBanner(fineText)
                    }
                    if let alert = location.currentAlert {
                        flitserCard(alert)
                    } else {
                        clearCard
                    }
                    statusFooter
                }
                .padding()
            }
            .navigationTitle("FlitsMaatje")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(location.isTracking ? "Stop" : "Start") {
                        if location.isTracking {
                            location.stop()
                        } else {
                            location.start()
                        }
                    }
                }
            }
        }
    }

    private var speedPanel: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(location.currentSpeedKmh.map(String.init) ?? "--")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSpeeding ? .red : .primary)
                Text("km/u")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let limit = location.speedLimit {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .strokeBorder(isSpeeding ? Color.red : Color.white.opacity(0.25), lineWidth: 3)
                            .frame(width: 56, height: 56)
                        Text("\(limit)")
                            .font(.title3.bold().monospacedDigit())
                    }
                    Text("limiet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isSpeeding ? Color.red.opacity(0.12) : Color(.secondarySystemBackground))
        )
    }

    private var isSpeeding: Bool {
        location.fineEstimate?.excess_kmh ?? 0 >= 4
    }

    private func fineBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text("🚨")
                .font(.title2)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
    }

    private func flitserCard(_ alert: NearbyAlert) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(alert.icon).font(.largeTitle)
                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.label)
                        .font(.headline)
                    Text("over \(alert.distance_m) m")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.red)
                }
                Spacer()
                Image(systemName: location.isTracking ? "bell.fill" : "bell.slash")
                    .foregroundStyle(.orange)
            }
            Text("Alarm bij naderen (600 → 400 → 200 → 100 m) + elke 25 s")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
        )
    }

    private var clearCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Geen flitsers in de buurt")
                .font(.headline)
            if let road = location.roadName {
                Text(road)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(location.statusText, systemImage: location.isTracking ? "location.fill" : "location.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Label("Ingebouwde navigatie: tab Navigatie — zoek of tik op kaart", systemImage: "1.circle")
            Label("Flitsalarm: geluid + trilling + melding", systemImage: "2.circle")
            Label("Boete-indicatie: indicatief, geen juridisch advies", systemImage: "3.circle")
            Label("CarPlay: stille boete-popup bij te hard rijden (geen spraak)", systemImage: "4.circle")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
