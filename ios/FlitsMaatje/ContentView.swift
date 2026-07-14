import SwiftUI

/// Licht dashboard — geen NavigationStack/DiagnosticLogView (crash op iOS 26).
struct ContentView: View {
    @EnvironmentObject private var location: LocationBackgroundService

    var body: some View {
        VStack(spacing: 0) {
            header
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
        }
        .background(Color(.systemBackground))
    }

    private var header: some View {
        HStack {
            Text("FlitsMaatje")
                .font(.title2.bold())
            Spacer()
            Button(location.isTracking ? "Stop" : "Start") {
                if location.isTracking {
                    location.stop()
                } else {
                    location.start()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
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
                            .strokeBorder(isSpeeding ? Color.red : Color.gray.opacity(0.3), lineWidth: 3)
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
        (location.fineEstimate?.excess_kmh ?? 0) >= 4
    }

    private func fineBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text("🚨").font(.title2)
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
                    Text(alert.label).font(.headline)
                    Text("over \(alert.distance_m) m")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.red)
                }
                Spacer()
                Image(systemName: location.isTracking ? "bell.fill" : "bell.slash")
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
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

            if location.managerAuthorizationIsWhenInUse {
                Button("Zet locatie op Altijd (CarPlay)") {
                    location.requestAlwaysPermission()
                }
                .font(.footnote.weight(.semibold))
            } else if location.managerAuthorizationIsAlways {
                Button("Achtergrond-tracking aanzetten") {
                    location.enableBackgroundTrackingIfAuthorized()
                }
                .font(.footnote.weight(.semibold))
            }

            Button("Log naar server sturen") {
                AppLogger.install()
                AppLogger.enableUIUpdates()
                AppLogger.uploadLogFile(reason: "manual-dashboard")
                BootLogger.uploadAsync()
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
