import MapKit
import SwiftUI

struct NavigationMapView: View {
    @EnvironmentObject private var location: LocationBackgroundService
    @EnvironmentObject private var navigation: NavigationService

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var didCenterOnUser = false
    @FocusState private var searchFocused: Bool
    @State private var favoriteToEdit: FavoriteDestinationKind?
    @State private var favoriteAddress = ""
    @State private var favoriteError: String?
    @State private var showingSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            VStack(spacing: 10) {
                searchBar
                favoriteButtons
                if navigation.isNavigating { turnBanner }
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
        .onChange(of: location.lastLocation) { _, newLocation in
            centerOnUserIfPossible()
            if let newLocation {
                navigation.updateProgress(location: newLocation)
                if navigation.isNavigating { followDrivingCamera(location: newLocation) }
            }
        }
        .alert(favoriteToEdit.map { "\($0.title) instellen" } ?? "Favoriet instellen", isPresented: Binding(
            get: { favoriteToEdit != nil }, set: { if !$0 { favoriteToEdit = nil } }
        )) {
            TextField("Adres", text: $favoriteAddress)
            Button("Opslaan") { saveFavorite() }
            Button("Annuleren", role: .cancel) { favoriteToEdit = nil }
        } message: { Text("Dit adres komt als snelle knop op je telefoon en in CarPlay.") }
        .alert("Favoriet niet opgeslagen", isPresented: Binding(
            get: { favoriteError != nil }, set: { if !$0 { favoriteError = nil } }
        )) { Button("OK", role: .cancel) { } } message: { Text(favoriteError ?? "") }
        .sheet(isPresented: $showingSettings) { settingsView }
    }

    private func centerOnUserIfPossible() {
        guard !didCenterOnUser, let user = location.lastLocation else { return }
        didCenterOnUser = true
        followDrivingCamera(location: user)
    }

    private func followDrivingCamera(location: CLLocation) {
        let heading = location.course >= 0 ? location.course : 0
        cameraPosition = .camera(MapCamera(
            centerCoordinate: location.coordinate,
            distance: navigation.isNavigating ? 650 : 900,
            heading: heading,
            pitch: navigation.isNavigating ? 58 : 42
        ))
    }

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: .all) {
                UserAnnotation()
                if let route = navigation.route {
                    MapPolyline(route.polyline).stroke(.blue, lineWidth: 7)
                }
                ForEach(location.mapReports) { report in
                    Annotation(report.label, coordinate: CLLocationCoordinate2D(latitude: report.lat, longitude: report.lng)) {
                        VStack(spacing: 1) {
                            Text(report.icon).font(.title3)
                            Text(report.label).font(.caption2.bold()).foregroundStyle(.white)
                        }
                        .padding(5)
                        .background(markerColor(for: report.type).opacity(0.95), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                if let alert = location.currentAlert {
                    Annotation(alert.label, coordinate: CLLocationCoordinate2D(latitude: alert.lat, longitude: alert.lng)) {
                        VStack(spacing: 2) {
                            Text(alert.icon).font(.title2)
                            Text("\(alert.distance_m) m").font(.caption2.bold()).foregroundStyle(.white)
                        }
                        .padding(7)
                        .background(.red.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                if let dest = navigation.route?.polyline.coordinates.last {
                    Marker(navigation.destinationName ?? "Bestemming", coordinate: dest)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: true))
            .mapControls { MapCompass(); MapUserLocationButton() }
            .onTapGesture { screenPoint in
                guard !navigation.isNavigating,
                      let coordinate = proxy.convert(screenPoint, from: .local),
                      let user = location.lastLocation else { return }
                searchFocused = false
                Task {
                    await navigation.startNavigation(to: coordinate, name: "Gekozen punt", from: user)
                    followDrivingCamera(location: user)
                }
            }
        }
    }

    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Waar naartoe?", text: $navigation.searchQuery)
                    .focused($searchFocused).submitLabel(.search)
                    .onSubmit { Task { await runSearch() } }
                if navigation.isNavigating {
                    Button("Stop") { navigation.stopNavigation() }.font(.subheadline.bold()).foregroundStyle(.red)
                }
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                }
            }
            .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            if searchFocused, !navigation.searchResults.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(navigation.searchResults.enumerated()), id: \.offset) { _, item in
                            Button {
                                guard let user = location.lastLocation else { return }
                                searchFocused = false
                                Task { await navigation.startNavigation(to: item, from: user); followDrivingCamera(location: user) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Locatie").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    if let subtitle = item.placemark.title { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).padding(.horizontal, 12)
                            }
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 180).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var favoriteButtons: some View {
        HStack(spacing: 8) { favoriteButton(for: .home); favoriteButton(for: .work) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func favoriteButton(for kind: FavoriteDestinationKind) -> some View {
        let configured = FavoriteDestinationStore.destination(for: kind) != nil
        return Button { startFavorite(kind) } label: {
            Label(configured ? kind.title : "\(kind.title) instellen", systemImage: kind.systemImage)
                .font(.subheadline.weight(.semibold)).lineLimit(1).padding(.horizontal, 12).padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func startFavorite(_ kind: FavoriteDestinationKind) {
        guard let favorite = FavoriteDestinationStore.destination(for: kind) else { favoriteAddress = ""; favoriteToEdit = kind; return }
        guard let user = location.lastLocation else { favoriteError = "Wacht tot GPS je locatie heeft gevonden."; return }
        Task { await navigation.startNavigation(to: favorite.mapItem, from: user); followDrivingCamera(location: user) }
    }

    private func saveFavorite() {
        guard let kind = favoriteToEdit else { return }
        Task {
            do { try await FavoriteDestinationStore.save(address: favoriteAddress, for: kind); favoriteToEdit = nil }
            catch { favoriteError = "Controleer het adres en probeer opnieuw." }
        }
    }

    private var turnBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").font(.title2).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(navigation.currentInstruction).font(.headline).lineLimit(2)
                HStack(spacing: 12) {
                    if navigation.distanceRemainingM > 0 { Text(formatDistance(navigation.distanceRemainingM)).font(.caption.monospacedDigit()) }
                    if let eta = navigation.eta { Text("ETA \(eta.formatted(date: .omitted, time: .shortened))").font(.caption) }
                }.foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var bottomHUD: some View {
        VStack(spacing: 8) {
            if let traffic = location.trafficInfo, let delay = traffic.delay_s, delay >= 60 {
                HStack(spacing: 8) {
                    Image(systemName: traffic.road_closure ? "exclamationmark.triangle.fill" : "car.fill")
                    Text(traffic.road_closure ? "Wegafsluiting gemeld" : "TomTom: +\(delay / 60) min vertraging")
                        .font(.caption.weight(.bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .padding(10)
                .background(Color.yellow.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            }
            if navigation.finesEnabled,
               let fineText = location.fineEstimate?.displayText(
                speedKmh: location.currentSpeedKmh,
                limit: location.speedLimit
               ) {
                HStack(spacing: 8) {
                    Image(systemName: "eurosign.circle.fill")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Boete-indicatie")
                            .font(.caption.weight(.bold))
                        Text(fineText)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: 290, alignment: .leading)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 13))
                .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("Boete-indicatie: \(fineText)")
            }
            if navigation.alertsEnabled, let alert = location.currentAlert {
                HStack(spacing: 12) {
                    Text(alert.icon).font(.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.label).font(.headline).foregroundStyle(.white)
                        Text("Over \(alert.distance_m) meter").font(.subheadline.bold()).foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                }.padding(12).background(Color.red.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
            }
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(location.currentSpeedKmh.map(String.init) ?? "--").font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("km/u").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let limit = location.speedLimit {
                    VStack(spacing: 2) {
                        Text("\(limit)").font(.title2.bold().monospacedDigit()).frame(width: 52, height: 52)
                            .background(.white, in: Circle()).foregroundStyle(.black)
                            .overlay(Circle().strokeBorder(.red, lineWidth: 5))
                        Text("limiet").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle(isOn: $navigation.voiceEnabled) { Image(systemName: navigation.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash") }.labelsHidden()
            }.padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func runSearch() async { guard let user = location.lastLocation else { return }; await navigation.search(near: user.coordinate) }
    private func formatDistance(_ meters: Int) -> String { meters >= 1000 ? String(format: "%.1f km", Double(meters) / 1000) : "\(meters) m" }

    private func markerColor(for type: String) -> Color {
        switch type {
        case "flitser_vast", "trajectcontrole": return .orange
        case "file": return .yellow
        case "ongeval": return .red
        case "wegwerkzaamheden": return .blue
        default: return .purple
        }
    }

    private var settingsView: some View {
        NavigationStack {
            Form {
                Section("Navigatie") {
                    Toggle("Automatisch herrouteren", isOn: $navigation.reroutingEnabled)
                    Toggle("Gesproken aanwijzingen", isOn: $navigation.voiceEnabled)
                }
                Section("Meldingen") {
                    Toggle("Boete-indicatie tonen", isOn: $navigation.finesEnabled)
                    Toggle("Verkeersmeldingen tonen", isOn: $navigation.alertsEnabled)
                }
            }
            .navigationTitle("Instellingen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") { showingSettings = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
