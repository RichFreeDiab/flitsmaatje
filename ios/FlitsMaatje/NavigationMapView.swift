import MapKit
import SwiftUI

struct NavigationMapView: View {
    @EnvironmentObject private var location: LocationBackgroundService
    @EnvironmentObject private var navigation: NavigationService

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var didCenterOnUser = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            VStack(spacing: 10) {
                searchBar
                if navigation.isNavigating {
                    turnBanner
                }
                Spacer()
                bottomHUD
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            AppLogger.log("NavigationMapView geladen")
            centerOnUserIfPossible()
        }
        .onChange(of: location.lastLocation) { _, _ in
            centerOnUserIfPossible()
        }
    }

    private func centerOnUserIfPossible() {
        guard !didCenterOnUser, location.lastLocation != nil else { return }
        didCenterOnUser = true
        cameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    }

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: .all) {
                UserAnnotation()

                if let route = navigation.route {
                    MapPolyline(route.polyline)
                        .stroke(.blue, lineWidth: 6)
                }

                if let alert = location.currentAlert {
                    Annotation(alert.label, coordinate: CLLocationCoordinate2D(latitude: alert.lat, longitude: alert.lng)) {
                        Text(alert.icon)
                            .font(.title2)
                            .padding(6)
                            .background(.red.opacity(0.9), in: Circle())
                    }
                }

                if let dest = navigation.route?.polyline.coordinates.last {
                    Marker(navigation.destinationName ?? "Bestemming", coordinate: dest)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapUserLocationButton()
            }
            .onTapGesture { screenPoint in
                guard !navigation.isNavigating,
                      let coordinate = proxy.convert(screenPoint, from: .local),
                      let user = location.lastLocation else { return }
                searchFocused = false
                Task {
                    await navigation.startNavigation(
                        to: coordinate,
                        name: "Gekozen punt",
                        from: user
                    )
                    followUser(heading: true)
                }
            }
        }
    }

    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Waar naartoe?", text: $navigation.searchQuery)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { Task { await runSearch() } }

                if navigation.isNavigating {
                    Button("Stop") { navigation.stopNavigation() }
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

            if searchFocused, !navigation.searchResults.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(navigation.searchResults.enumerated()), id: \.offset) { _, item in
                            Button {
                                guard let user = location.lastLocation else { return }
                                searchFocused = false
                                Task {
                                    await navigation.startNavigation(to: item, from: user)
                                    followUser(heading: true)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Locatie")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if let subtitle = item.placemark.title {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                            }
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 180)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var turnBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(navigation.currentInstruction)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    if navigation.distanceRemainingM > 0 {
                        Text(formatDistance(navigation.distanceRemainingM))
                            .font(.caption.monospacedDigit())
                    }
                    if let eta = navigation.eta {
                        Text("ETA \(eta.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var bottomHUD: some View {
        VStack(spacing: 8) {
            if let fineText = location.fineEstimate?.displayText {
                Text("🚨 \(fineText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
            }

            if let alert = location.currentAlert {
                HStack {
                    Text(alert.icon).font(.title2)
                    VStack(alignment: .leading) {
                        Text(alert.label).font(.subheadline.bold())
                        Text("over \(alert.distance_m) m").font(.caption).foregroundStyle(.red)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            }

            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(location.currentSpeedKmh.map(String.init) ?? "--")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("km/u").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let limit = location.speedLimit {
                    VStack(spacing: 2) {
                        Text("\(limit)")
                            .font(.title2.bold().monospacedDigit())
                            .frame(width: 52, height: 52)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 2))
                        Text("limiet").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle(isOn: $navigation.voiceEnabled) {
                    Image(systemName: navigation.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                }
                .labelsHidden()
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func runSearch() async {
        guard let user = location.lastLocation else { return }
        await navigation.search(near: user.coordinate)
    }

    private func followUser(heading: Bool) {
        cameraPosition = .userLocation(followsHeading: heading, fallback: .automatic)
    }

    private func formatDistance(_ meters: Int) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", Double(meters) / 1000)
        }
        return "\(meters) m"
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
