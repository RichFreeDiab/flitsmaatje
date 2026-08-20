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
                if navigation.isNavigating {
                    maneuverBanner
                } else {
                    directionHUD
                }
                favoriteButtons
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
                ForEach(location.mapReports.filter { $0.type != "flitser_vast" && $0.type != "flitser_mobiel" && $0.type != "trajectcontrole" }) { report in
                    Annotation(report.label, coordinate: CLLocationCoordinate2D(latitude: report.lat, longitude: report.lng)) {
                        VStack(spacing: 1) {
                            Text(report.icon).font(.title3)
                            Text(report.label).font(.caption2.bold()).foregroundStyle(.white)
                        }
                        .padding(5)
                        .background(markerColor(for: report.type).opacity(0.95), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                ForEach(location.mapReports.filter { ["flitser_vast", "flitser_mobiel", "trajectcontrole"].contains($0.type) }) { report in
                    Annotation("Vaste flitspaal", coordinate: CLLocationCoordinate2D(latitude: report.lat, longitude: report.lng)) {
                        VStack(spacing: 2) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.red, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                            Text("Flitspaal")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.red.opacity(0.95), in: Capsule())
                        }
                    }
                }
                if let alert = location.currentAlert {
                    Annotation(alert.label, coordinate: CLLocationCoordinate2D(latitude: alert.lat, longitude: alert.lng)) {
                        VStack(spacing: 2) {
                            Text(alert.icon).font(.title2)
                            Text(String(format: "%.1f km", Double(alert.distance_m) / 1000)).font(.caption2.bold()).foregroundStyle(.white)
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

    private var directionHUD: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: directionArrowSymbol)
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(directionArrowRotation))
                .frame(width: 66, height: 66)
                .background(Color.black.opacity(0.82), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                if navigation.isNavigating, let section = activeLaneSection {
                    googleMapsLaneStrip(section, cellSize: 34, arrowSize: 22)
                    if let laneHint = NavigationService.laneRecommendationText(for: section) {
                        Text(laneHint)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(2)
                    }
                }
                if navigation.isNavigating, let exit = navigation.currentOrUpcomingExitBannerText {
                    Text(exit)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                } else {
                    Text(directionTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(directionSubtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 360, alignment: .leading)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(navigation.isNavigating ? (navigation.guidanceDetailText ?? "Navigeren") : "Permanente richting en rijbaan")
    }

    private var courseDegrees: Double? {
        guard let loc = location.lastLocation, loc.course >= 0 else { return nil }
        return loc.course
    }

    private var directionArrowSymbol: String {
        if navigation.isNavigating {
            return maneuverSymbol(for: navigation.currentInstruction)
        }
        return "arrow.up"
    }

    private var directionArrowRotation: Double {
        // Bij navigatie: maneuver-icoon rechtop; anders koerspijl draait mee.
        if navigation.isNavigating { return 0 }
        return courseDegrees ?? 0
    }

    private var activeLaneSection: LaneSection? {
        guard navigation.isNavigating else { return nil }
        return navigation.laneSections.first(where: { navigation.shouldShowLaneSection($0) })
    }

    private var directionTitle: String {
        if navigation.isNavigating {
            return navigation.currentOrUpcomingExitBannerText ?? navigation.currentExitBannerText ?? "Navigeren"
        }
        if let deg = courseDegrees {
            return "Koers \(compassLabel(deg))"
        }
        return "Richting…"
    }

    private var directionSubtitle: String {
        if let deg = courseDegrees {
            return "\(Int(deg.rounded()))° \(compassLabel(deg))"
        }
        return "Wacht op GPS-koers"
    }

    private func compassLabel(_ deg: Double) -> String {
        let names = ["N", "NO", "O", "ZO", "Z", "ZW", "W", "NW"]
        let idx = Int(((deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 45.0).rounded()) % 8
        return names[idx]
    }

    private var maneuverBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: maneuverSymbol(for: navigation.currentInstruction))
                    .font(.system(size: 52, weight: .bold))
                    .frame(width: 72, height: 72)
                    .foregroundStyle(.white)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    if let meters = navigation.laneGuidanceDistanceM
                        ?? (navigation.currentManeuverDistanceM > 0 ? navigation.currentManeuverDistanceM : nil) {
                        Text(formatGuidanceDistance(meters))
                            .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    if let exitText = navigation.currentOrUpcomingExitBannerText {
                        Text(exitText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                    } else {
                        Text(navigation.currentInstruction)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            if let section = activeLaneSection {
                // Flitsmeister/Google: banenstrip onder de pijl
                googleMapsLaneStrip(section, cellSize: 48, arrowSize: 26)
            }
        }
        .onChange(of: location.mapReports) { _, reports in
            navigation.updateTrafficReports(reports)
        }
        .padding(14)
        .frame(maxWidth: 380, alignment: .leading)
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Flitsmeister-stijl: donkere banen, volg-pijl helder wit, rest gedimd.
    private func googleMapsLaneStrip(_ section: LaneSection, cellSize: CGFloat, arrowSize: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(section.lanes.enumerated()), id: \.offset) { _, lane in
                let follow = lane.follow
                let isFollow = follow != nil
                let arrows = laneArrowDirections(lane)
                VStack(spacing: 1) {
                    ForEach(Array(arrows.enumerated()), id: \.offset) { _, dir in
                        Image(systemName: laneSymbol(dir))
                            .font(.system(size: arrowSize, weight: dir == follow ? .heavy : .semibold))
                            .foregroundStyle(
                                dir == follow
                                    ? Color.white
                                    : Color.white.opacity(isFollow ? 0.22 : 0.38)
                            )
                    }
                }
                .frame(width: cellSize, height: max(cellSize + 6, CGFloat(max(arrows.count, 1)) * (arrowSize + 3) + 8))
                .background(
                    isFollow ? Color.white.opacity(0.18) : Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isFollow ? Color.white.opacity(0.55) : Color.clear, lineWidth: 1.5)
                )
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("Rijstroken")
    }

    private func laneArrowDirections(_ lane: Lane) -> [String] {
        var dirs = lane.directions
        if let follow = lane.follow, !dirs.contains(follow) {
            dirs.append(follow)
        }
        if dirs.isEmpty { return ["STRAIGHT"] }
        return dirs
    }

    private func maneuverSymbol(for instruction: String) -> String {
        let text = instruction.lowercased()
        if text.contains("rotonde") { return "arrow.clockwise" }
        if text.contains("keer") || text.contains("u-turn") { return "arrow.uturn.backward" }
        if text.contains("links") || text.contains("left") { return "arrow.turn.up.left" }
        if text.contains("rechts") || text.contains("right") { return "arrow.turn.up.right" }
        if text.contains("afrit") || text.contains("exit") { return "arrow.turn.up.right" }
        return "arrow.up"
    }

    private func laneSymbol(_ direction: String?) -> String {
        switch (direction ?? "").uppercased() {
        case "LEFT": return "arrow.up.left"
        case "SLIGHT_LEFT": return "arrow.up.left"
        case "SHARP_LEFT": return "arrow.uturn.up"
        case "RIGHT": return "arrow.up.right"
        case "SLIGHT_RIGHT": return "arrow.up.right"
        case "SHARP_RIGHT": return "arrow.uturn.up"
        case "LEFT_U_TURN", "RIGHT_U_TURN", "U_TURN": return "arrow.uturn.up"
        default: return "arrow.up"
        }
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
            if navigation.finesEnabled, let fineText = location.fineStatusText {
                HStack(spacing: 8) {
                    Image(systemName: "eurosign.circle.fill")
                        .font(.headline)
                    Text(fineText)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(fineText == "Boete —" ? Color.white : Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: 290, alignment: .leading)
                .background(fineText == "Boete —" ? Color.gray : Color.orange, in: RoundedRectangle(cornerRadius: 13))
                .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("Boete-indicatie: \(fineText)")
            }
            if navigation.alertsEnabled, let alert = location.currentAlert {
                HStack(spacing: 12) {
                    Text(alert.icon).font(.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.label).font(.headline).foregroundStyle(.white)
                        Text(String(format: "Over %.1f km", Double(alert.distance_m) / 1000)).font(.subheadline.bold()).foregroundStyle(.white.opacity(0.9))
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
            }.padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func runSearch() async { guard let user = location.lastLocation else { return }; await navigation.search(near: user.coordinate) }
    private func formatGuidanceDistance(_ meters: Int) -> String {
        meters < 1_000
            ? "\(max(10, Int((Double(meters) / 10).rounded()) * 10)) m"
            : String(format: "%.1f km", Double(meters) / 1_000)
    }

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
                }
                Section("Meldingen") {
                    Toggle("Boete-indicatie tonen", isOn: $navigation.finesEnabled)
                    Toggle("Verkeersmeldingen tonen", isOn: $navigation.alertsEnabled)
                    Toggle("Gesproken waarschuwingen", isOn: $navigation.voiceEnabled)
                    Toggle("Boetemelding aan/uit", isOn: $navigation.finesEnabled)
                }
                Section {
                    Text("Uit: alleen alarmtoon en trilling. Aan: ook gesproken route- en flitserwaarschuwingen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
