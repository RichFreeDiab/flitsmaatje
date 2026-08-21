import CoreLocation
import MapKit
import UIKit

private final class ReportMapAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let reportType: String
    let title: String?

    init(report: MapReport) {
        coordinate = CLLocationCoordinate2D(latitude: report.lat, longitude: report.lng)
        reportType = report.type
        title = report.label
        super.init()
    }
}

final class CarPlayMapViewController: UIViewController, MKMapViewDelegate {
    let mapView = MKMapView()
    private let speedLabel = UILabel()
    private let speedUnitLabel = UILabel()
    private let limitLabel = UILabel()
    private let alertLabel = UILabel()
    private let fineLabel = UILabel()
    private let laneLabel = UILabel()
    private let maneuverLabel = UILabel()
    private let alertPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let finePanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let lanePanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let maneuverPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private var refreshTimer: Timer?
    private var reportSignature = ""
    private var alertBottomToFineConstraint: NSLayoutConstraint?
    private var alertBottomToSafeAreaConstraint: NSLayoutConstraint?
    private var lastCameraUpdateAt = Date.distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsTraffic = true
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(
            minCenterCoordinateDistance: 180,
            maxCenterCoordinateDistance: 900
        )
        view.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor), mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor), mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        configureOverlay()
        refreshOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshOverlay() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        refreshTimer?.invalidate(); refreshTimer = nil
    }

    private func refreshOverlay() {
        let snapshot = SharedStore.load()
        let alertText = snapshot.alert.map { "\($0.icon) \($0.label)  •  over \($0.distance_m) m" }
        update(speedKmh: snapshot.speedKmh, limit: snapshot.speedLimitKmh, alert: alertText, fineText: snapshot.fineText)
    }

    private func configureOverlay() {
        let statusPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        statusPanel.translatesAutoresizingMaskIntoConstraints = false; statusPanel.layer.cornerRadius = 12; statusPanel.clipsToBounds = true
        statusPanel.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        view.addSubview(statusPanel)
        speedLabel.textColor = .white; speedLabel.font = .monospacedDigitSystemFont(ofSize: 31, weight: .bold); speedLabel.text = "--"; speedLabel.textAlignment = .center
        speedUnitLabel.textColor = UIColor.white.withAlphaComponent(0.78); speedUnitLabel.font = .systemFont(ofSize: 13, weight: .semibold); speedUnitLabel.text = "km/u"; speedUnitLabel.textAlignment = .center
        limitLabel.textColor = .black; limitLabel.backgroundColor = .white; limitLabel.font = .monospacedDigitSystemFont(ofSize: 25, weight: .bold); limitLabel.textAlignment = .center
        limitLabel.layer.cornerRadius = 29; limitLabel.layer.borderWidth = 4; limitLabel.layer.borderColor = UIColor.systemRed.cgColor; limitLabel.clipsToBounds = true
        alertLabel.font = .systemFont(ofSize: 18, weight: .bold); alertLabel.numberOfLines = 2; alertLabel.textAlignment = .left
        fineLabel.font = .monospacedDigitSystemFont(ofSize: 19, weight: .bold); fineLabel.numberOfLines = 2; fineLabel.textAlignment = .left; fineLabel.adjustsFontSizeToFitWidth = true; fineLabel.minimumScaleFactor = 0.72
        laneLabel.font = .systemFont(ofSize: 44, weight: .bold); laneLabel.textAlignment = .center; laneLabel.textColor = .white
        lanePanel.isHidden = true
        maneuverLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold); maneuverLabel.numberOfLines = 1; maneuverLabel.textColor = .white; maneuverLabel.textAlignment = .left

        let currentSpeedStack = UIStackView(arrangedSubviews: [speedLabel, speedUnitLabel])
        currentSpeedStack.axis = .vertical
        currentSpeedStack.spacing = -3
        currentSpeedStack.alignment = .center
        let speedStack = UIStackView(arrangedSubviews: [limitLabel, currentSpeedStack]); speedStack.axis = .horizontal; speedStack.spacing = 10; speedStack.alignment = .center
        speedStack.translatesAutoresizingMaskIntoConstraints = false; statusPanel.contentView.addSubview(speedStack)

        [alertPanel, finePanel, lanePanel, maneuverPanel].forEach { panel in panel.translatesAutoresizingMaskIntoConstraints = false; panel.layer.cornerRadius = 12; panel.clipsToBounds = true; view.addSubview(panel) }
        lanePanel.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.94)
        maneuverPanel.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.94)
        alertPanel.contentView.backgroundColor = UIColor(red: 0.24, green: 0.13, blue: 0.02, alpha: 0.94)
        finePanel.contentView.backgroundColor = UIColor(red: 0.32, green: 0.05, blue: 0.04, alpha: 0.96)
        alertLabel.translatesAutoresizingMaskIntoConstraints = false; fineLabel.translatesAutoresizingMaskIntoConstraints = false; laneLabel.translatesAutoresizingMaskIntoConstraints = false; maneuverLabel.translatesAutoresizingMaskIntoConstraints = false
        alertPanel.contentView.addSubview(alertLabel); finePanel.contentView.addSubview(fineLabel); lanePanel.contentView.addSubview(laneLabel); maneuverPanel.contentView.addSubview(maneuverLabel)

        alertBottomToFineConstraint = alertPanel.bottomAnchor.constraint(equalTo: finePanel.topAnchor, constant: -1)
        alertBottomToSafeAreaConstraint = alertPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)

        NSLayoutConstraint.activate([
            statusPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12), statusPanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            speedStack.topAnchor.constraint(equalTo: statusPanel.contentView.topAnchor, constant: 9), speedStack.bottomAnchor.constraint(equalTo: statusPanel.contentView.bottomAnchor, constant: -9), speedStack.leadingAnchor.constraint(equalTo: statusPanel.contentView.leadingAnchor, constant: 11), speedStack.trailingAnchor.constraint(equalTo: statusPanel.contentView.trailingAnchor, constant: -11),
            limitLabel.widthAnchor.constraint(equalToConstant: 58), limitLabel.heightAnchor.constraint(equalToConstant: 58),
            lanePanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18), lanePanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14), lanePanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 190), lanePanel.widthAnchor.constraint(lessThanOrEqualToConstant: 330),
            maneuverPanel.leadingAnchor.constraint(equalTo: lanePanel.leadingAnchor), maneuverPanel.trailingAnchor.constraint(equalTo: lanePanel.trailingAnchor), maneuverPanel.topAnchor.constraint(equalTo: lanePanel.bottomAnchor, constant: -1),
            maneuverLabel.topAnchor.constraint(equalTo: maneuverPanel.contentView.topAnchor, constant: 8), maneuverLabel.bottomAnchor.constraint(equalTo: maneuverPanel.contentView.bottomAnchor, constant: -8), maneuverLabel.leadingAnchor.constraint(equalTo: maneuverPanel.contentView.leadingAnchor, constant: 12), maneuverLabel.trailingAnchor.constraint(equalTo: maneuverPanel.contentView.trailingAnchor, constant: -12),
            laneLabel.topAnchor.constraint(equalTo: lanePanel.contentView.topAnchor, constant: 12), laneLabel.bottomAnchor.constraint(equalTo: lanePanel.contentView.bottomAnchor, constant: -6), laneLabel.leadingAnchor.constraint(equalTo: lanePanel.contentView.leadingAnchor, constant: 12), laneLabel.trailingAnchor.constraint(equalTo: lanePanel.contentView.trailingAnchor, constant: -12),
            alertPanel.leadingAnchor.constraint(greaterThanOrEqualTo: view.centerXAnchor, constant: 12), alertPanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14), alertPanel.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
            alertLabel.topAnchor.constraint(equalTo: alertPanel.contentView.topAnchor, constant: 10), alertLabel.bottomAnchor.constraint(equalTo: alertPanel.contentView.bottomAnchor, constant: -10), alertLabel.leadingAnchor.constraint(equalTo: alertPanel.contentView.leadingAnchor, constant: 12), alertLabel.trailingAnchor.constraint(equalTo: alertPanel.contentView.trailingAnchor, constant: -12),
            finePanel.leadingAnchor.constraint(equalTo: alertPanel.leadingAnchor), finePanel.trailingAnchor.constraint(equalTo: alertPanel.trailingAnchor), finePanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            fineLabel.topAnchor.constraint(equalTo: finePanel.contentView.topAnchor, constant: 10), fineLabel.bottomAnchor.constraint(equalTo: finePanel.contentView.bottomAnchor, constant: -10), fineLabel.leadingAnchor.constraint(equalTo: finePanel.contentView.leadingAnchor, constant: 12), fineLabel.trailingAnchor.constraint(equalTo: finePanel.contentView.trailingAnchor, constant: -12)
        ])
        alertBottomToSafeAreaConstraint?.isActive = true
    }

    func update(speedKmh: Int?, limit: Int?, alert: String?, fineText: String?) {
        speedLabel.text = speedKmh.map(String.init) ?? "--"
        limitLabel.text = limit.map(String.init) ?? "--"
        limitLabel.isHidden = limit == nil
        alertLabel.text = alert
        alertLabel.textColor = .systemOrange
        alertPanel.isHidden = alert == nil

        // De native CPMapTemplate blijft de enige route-/lane-laag.
        // Toon alleen een echte boete; placeholders zoals "Boete —" nooit.
        let hasFine = fineText.map { text in
            let normalized = text.replacingOccurrences(of: "Boete", with: "")
                .replacingOccurrences(of: "—", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !normalized.isEmpty
        } ?? false
        if hasFine, let fineText {
            fineLabel.text = compactFineText(fineText, speedKmh: speedKmh)
        } else {
            fineLabel.text = nil
        }
        fineLabel.textColor = .white
        finePanel.isHidden = !hasFine
        // Geen lane/maneuver hier verbergen: dat deed update() elke seconde
        // via speed/boete-refresh en wiste Flitsmeister-banenstrip.

        // Eerst beide uitzetten om tijdelijke conflicterende Auto Layout-
        // constraints tijdens een live waarschuwing te voorkomen.
        alertBottomToFineConstraint?.isActive = false
        alertBottomToSafeAreaConstraint?.isActive = false
        if alert != nil {
            if hasFine {
                alertBottomToFineConstraint?.isActive = true
            } else {
                alertBottomToSafeAreaConstraint?.isActive = true
            }
        }
        if hasFine {
            view.bringSubviewToFront(finePanel)
        }
        if alert != nil {
            view.bringSubviewToFront(alertPanel)
        }
        view.bringSubviewToFront(lanePanel)
        view.bringSubviewToFront(maneuverPanel)
    }

    private func compactFineText(_ text: String, speedKmh: Int?) -> String {
        let prefix = speedKmh.map { "Boete bij \($0) km/u: " } ?? "Boete: "
        if let euroIndex = text.firstIndex(of: "€") {
            let afterEuro = text[text.index(after: euroIndex)...]
            let amount = afterEuro
                .drop(while: { $0.isWhitespace })
                .prefix { $0.isNumber || $0 == "." || $0 == "," }
            if !amount.isEmpty {
                return "\(prefix)€ \(amount)"
            }
        }
        if text.localizedCaseInsensitiveContains("OM") {
            return "\(prefix)OM-tarief"
        }
        return text
    }

    /// Compacte fallback alleen vóór native CarPlay-navigatie (geen dubbele pijlen).
    func updateManeuver(
        instruction: String?,
        distanceText: String?,
        detailText: String? = nil,
        laneSections: [LaneSection] = [],
        showFallback: Bool = false
    ) {
        guard showFallback else {
            // Native CPManeuver + CPLaneGuidance zijn de enige navigatie-UI.
            laneLabel.text = nil
            lanePanel.isHidden = true
            maneuverLabel.text = nil
            maneuverPanel.isHidden = true
            return
        }

        let section = laneSections.first
        let laneStrip = section.map(Self.flitsmeisterLaneStripText)
        let hasLaneStrip = !(laneStrip?.isEmpty ?? true)

        if hasLaneStrip, let laneStrip {
            laneLabel.text = laneStrip
            laneLabel.font = .systemFont(ofSize: 22, weight: .bold)
            laneLabel.numberOfLines = 1
            laneLabel.adjustsFontSizeToFitWidth = true
            laneLabel.minimumScaleFactor = 0.6
            lanePanel.isHidden = false
            view.bringSubviewToFront(lanePanel)
        } else {
            laneLabel.text = nil
            lanePanel.isHidden = true
        }

        var lines: [String] = []
        if let distanceText, !distanceText.isEmpty {
            lines.append(distanceText)
        }
        if let detailText, !detailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(detailText)
        } else if let instruction, !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(instruction)
        }

        if !lines.isEmpty {
            maneuverLabel.text = lines.joined(separator: " · ")
            maneuverLabel.numberOfLines = 2
            maneuverLabel.font = .systemFont(ofSize: 18, weight: .semibold)
            maneuverPanel.isHidden = false
            view.bringSubviewToFront(maneuverPanel)
        } else {
            maneuverLabel.text = nil
            maneuverPanel.isHidden = true
        }
    }

    /// Compacte unicode-banen: één pijl per strook, volg tussen 【 】.
    private static func flitsmeisterLaneStripText(_ section: LaneSection) -> String {
        guard !section.lanes.isEmpty else { return "" }
        return section.lanes.map { lane -> String in
            let primary = (lane.follow ?? lane.directions.first ?? "STRAIGHT").uppercased()
            let symbol = laneArrowGlyph(primary)
            return lane.follow != nil ? "【\(symbol)】" : symbol
        }.joined(separator: " ")
    }

    private static func laneArrowGlyph(_ direction: String) -> String {
        switch direction.uppercased() {
        case "LEFT", "SLIGHT_LEFT": return "↖"
        case "SHARP_LEFT", "LEFT_U_TURN": return "↰"
        case "RIGHT", "SLIGHT_RIGHT": return "↗"
        case "SHARP_RIGHT", "RIGHT_U_TURN": return "↱"
        case "U_TURN": return "↩"
        default: return "↑"
        }
    }

    func updateFromSnapshot(_ snapshot: WidgetSnapshot) {
        let alertText = snapshot.alert.map { "\($0.icon) \($0.label)  •  over \($0.distance_m) m" }
        update(speedKmh: snapshot.speedKmh, limit: snapshot.speedLimitKmh, alert: alertText, fineText: snapshot.fineText)
    }

    func updateReports(_ reports: [MapReport]) {
        let signature = reports
            .map { "\($0.id):\($0.lat):\($0.lng):\($0.type)" }
            .sorted()
            .joined(separator: "|")
        guard signature != reportSignature else { return }
        reportSignature = signature

        let oldAnnotations = mapView.annotations.compactMap { $0 as? ReportMapAnnotation }
        mapView.removeAnnotations(oldAnnotations)
        mapView.addAnnotations(reports.map(ReportMapAnnotation.init))
    }

    func showRoute(_ route: MKRoute) { mapView.removeOverlays(mapView.overlays); mapView.addOverlay(route.polyline); recenter() }

    func follow(location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 80 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCameraUpdateAt) >= 0.35 else { return }
        lastCameraUpdateAt = now
        let heading = location.course >= 0 ? location.course : mapView.camera.heading
        let speedKmh = max(0, location.speed * 3.6)
        let cameraDistance: CLLocationDistance = speedKmh >= 80 ? 560 : (speedKmh >= 40 ? 440 : 340)
        let lookAhead = max(45, min(180, max(0, location.speed) * 6))
        let center = coordinate(from: location.coordinate, distance: lookAhead, bearing: heading)
        let camera = MKMapCamera(lookingAtCenter: center, fromDistance: cameraDistance, pitch: 64, heading: heading)
        // Geen overlappende camera-animaties bij snelle GPS-updates: dat was
        // de belangrijkste oorzaak van haperen tijdens het rijden.
        mapView.setCamera(camera, animated: false)
    }

    private func coordinate(
        from coordinate: CLLocationCoordinate2D,
        distance: CLLocationDistance,
        bearing: CLLocationDirection
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let angularDistance = distance / earthRadius
        let bearingRadians = bearing * .pi / 180
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        let nextLatitude = asin(
            sin(latitude) * cos(angularDistance)
                + cos(latitude) * sin(angularDistance) * cos(bearingRadians)
        )
        let nextLongitude = longitude + atan2(
            sin(bearingRadians) * sin(angularDistance) * cos(latitude),
            cos(angularDistance) - sin(latitude) * sin(nextLatitude)
        )
        return CLLocationCoordinate2D(
            latitude: nextLatitude * 180 / .pi,
            longitude: nextLongitude * 180 / .pi
        )
    }

    func clearRoute() { mapView.removeOverlays(mapView.overlays) }
    func showNavigationError(_ message: String) { alertPanel.isHidden = false; alertLabel.text = "⚠️ " + message; alertLabel.textColor = .systemRed }
    func recenter() { if let location = mapView.userLocation.location { follow(location: location) } }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline { let renderer = MKPolylineRenderer(polyline: polyline); renderer.strokeColor = .systemBlue; renderer.lineWidth = 7; return renderer }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let report = annotation as? ReportMapAnnotation else { return nil }
        let identifier = "FlitsMaatjeReport"
        let marker = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: report, reuseIdentifier: identifier)
        marker.annotation = report
        marker.canShowCallout = true
        marker.glyphImage = UIImage(systemName: glyphName(for: report.reportType))
        marker.markerTintColor = markerTintColor(for: report.reportType)
        marker.displayPriority = report.reportType == "flitser_vast" ? .required : .defaultHigh
        return marker
    }

    private func glyphName(for type: String) -> String {
        switch type {
        case "flitser_vast": return "camera.fill"
        case "flitser_mobiel": return "car.fill"
        case "trajectcontrole": return "dot.radiowaves.left.and.right"
        case "file": return "car.2.fill"
        case "ongeval": return "exclamationmark.triangle.fill"
        case "wegwerkzaamheden": return "wrench.and.screwdriver.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private func markerTintColor(for type: String) -> UIColor {
        switch type {
        case "flitser_vast", "flitser_mobiel", "trajectcontrole": return .systemRed
        case "file": return .systemOrange
        case "ongeval": return .systemPink
        case "wegwerkzaamheden": return .systemYellow
        default: return .systemBlue
        }
    }
}
