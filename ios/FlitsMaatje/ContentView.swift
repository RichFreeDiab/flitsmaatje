import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var location: LocationBackgroundService

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: location.isTracking ? "location.fill" : "location.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(location.isTracking ? .green : .orange)

                Text("FlitsMaatje CarPlay")
                    .font(.title2.bold())

                Text(location.statusText)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if let alert = location.currentAlert {
                    VStack(spacing: 8) {
                        Text(alert.icon).font(.largeTitle)
                        Text(alert.label).font(.headline)
                        Text("over \(alert.distance_m) m")
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    Text("Geen waarschuwing actief")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Laat de app op de achtergrond draaien tijdens rijden", systemImage: "1.circle")
                    Label("Voeg het widget toe in Instellingen → Algemeen → CarPlay → [auto]", systemImage: "2.circle")
                    Label("Navigeer met Kaarten of Google Maps — het widget verschijnt naast je route", systemImage: "3.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
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
        .onAppear {
            location.requestPermissionAndStart()
        }
    }
}
