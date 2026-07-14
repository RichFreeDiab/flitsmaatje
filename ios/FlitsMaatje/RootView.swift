import SwiftUI

struct RootView: View {
    @State private var location: LocationBackgroundService?
    @State private var isStarting = false

    var body: some View {
        Group {
            if let location {
                ContentView()
                    .environmentObject(location)
                    .onChange(of: location.currentAlert) { _, alert in
                        CarPlayDrivingTaskCoordinator.shared.update(alert: alert)
                    }
            } else {
                VStack(spacing: 24) {
                    Text("FlitsMaatje")
                        .font(.largeTitle.bold())
                    Text("Flitsers & boete-indicatie")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(isStarting ? "Starten…" : "Start FlitsMaatje") {
                        startApp()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStarting)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            BootLogger.mark("rootview-onAppear")
            BootLogger.uploadAsync()
        }
    }

    private func startApp() {
        guard !isStarting else { return }
        isStarting = true
        BootLogger.mark("user-start-tap")

        let service = LocationBackgroundService()
        location = service
        CarPlayDrivingTaskCoordinator.shared.locationService = service
        BootLogger.mark("location-created")

        service.requestPermissionAndStart()
        service.activateWhenReady()
        BootLogger.mark("bootstrap-complete")
        BootLogger.uploadAsync()
        isStarting = false
    }
}
