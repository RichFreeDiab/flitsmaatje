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
        view.addSubview(statusPanel)
        speedLabel.textColor = .white; speedLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold); speedLabel.text = "--"
        limitLabel.textColor = .white; limitLabel.font = .systemFont(ofSize: 15, weight: .bold)
        alertLabel.font = .systemFont(ofSize: 17, weight: .bold); alertLabel.numberOfLines = 2; alertLabel.textAlignment = .center
        fineLabel.font = .systemFont(ofSize: 20, weight: .bold); fineLabel.numberOfLines = 1; fineLabel.textAlignment = .center; fineLabel.adjustsFontSizeToFitWidth = true; fineLabel.minimumScaleFactor = 0.75
        laneLabel.font = .systemFont(ofSize: 22, weight: .bold); laneLabel.textAlignment = .center; laneLabel.textColor = .white
        lanePanel.isHidden = true
        maneuverLabel.font = .systemFont(ofSize: 36, weight: .bold); maneuverLabel.numberOfLines = 1; maneuverLabel.textColor = .white; maneuverLabel.textAlignment = .center

        let speedStack = UIStackView(arrangedSubviews: [speedLabel, limitLabel]); speedStack.axis = .horizontal; speedStack.spacing = 8; speedStack.alignment = .firstBaseline
        speedStack.translatesAutoresizingMaskIntoConstraints = false; statusPanel.contentView.addSubview(speedStack)

        [alertPanel, finePanel, lanePanel, maneuverPanel].forEach { panel in panel.translatesAutoresizingMaskIntoConstraints = false; panel.layer.cornerRadius = 12; panel.clipsToBounds = true; view.addSubview(panel) }
        alertLabel.translatesAutoresizingMaskIntoConstraints = false; fineLabel.translatesAutoresizingMaskIntoConstraints = false; laneLabel.translatesAutoresizingMaskIntoConstraints = false; maneuverLabel.translatesAutoresizingMaskIntoConstraints = false
        alertPanel.contentView.addSubview(alertLabel); finePanel.contentView.addSubview(fineLabel); lanePanel.contentView.addSubview(laneLabel); maneuverPanel.contentView.addSubview(maneuverLabel)

        NSLayoutConstraint.activate([
            statusPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12), statusPanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            speedStack.topAnchor.constraint(equalTo: statusPanel.contentView.topAnchor, constant: 9), speedStack.bottomAnchor.constraint(equalTo: statusPanel.contentView.bottomAnchor, constant: -9), speedStack.leadingAnchor.constraint(equalTo: statusPanel.contentView.leadingAnchor, constant: 11), speedStack.trailingAnchor.constraint(equalTo: statusPanel.contentView.trailingAnchor, constant: -11),
            maneuverPanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18), maneuverPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14), maneuverPanel.widthAnchor.constraint(lessThanOrEqualToConstant: 330),
            maneuverLabel.topAnchor.constraint(equalTo: maneuverPanel.contentView.topAnchor, constant: 8), maneuverLabel.bottomAnchor.constraint(equalTo: maneuverPanel.contentView.bottomAnchor, constant: -8), maneuverLabel.leadingAnchor.constraint(equalTo: maneuverPanel.contentView.leadingAnchor, constant: 12), maneuverLabel.trailingAnchor.constraint(equalTo: maneuverPanel.contentView.trailingAnchor, constant: -12),
            lanePanel.leadingAnchor.constraint(equalTo: maneuverPanel.leadingAnchor), lanePanel.trailingAnchor.constraint(equalTo: maneuverPanel.trailingAnchor), lanePanel.topAnchor.constraint(equalTo: maneuverPanel.bottomAnchor, constant: 6),
            laneLabel.topAnchor.constraint(equalTo: lanePanel.contentView.topAnchor, constant: 6), laneLabel.bottomAnchor.constraint(equalTo: lanePanel.contentView.bottomAnchor, constant: -6), laneLabel.leadingAnchor.constraint(equalTo: lanePanel.contentView.leadingAnchor, constant: 12), laneLabel.trailingAnchor.constraint(equalTo: lanePanel.contentView.trailingAnchor, constant: -12),
            alertPanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18), alertPanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18), alertPanel.bottomAnchor.constraint(equalTo: finePanel.topAnchor, constant: -8),
            alertLabel.topAnchor.constraint(equalTo: alertPanel.contentView.topAnchor, constant: 10), alertLabel.bottomAnchor.constraint(equalTo: alertPanel.contentView.bottomAnchor, constant: -10), alertLabel.leadingAnchor.constraint(equalTo: alertPanel.contentView.leadingAnchor, constant: 12), alertLabel.trailingAnchor.constraint(equalTo: alertPanel.contentView.trailingAnchor, constant: -12),
            finePanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14), finePanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16), finePanel.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            fineLabel.topAnchor.constraint(equalTo: finePanel.contentView.topAnchor, constant: 10), fineLabel.bottomAnchor.constraint(equalTo: finePanel.contentView.bottomAnchor, constant: -10), fineLabel.leadingAnchor.constraint(equalTo: finePanel.contentView.leadingAnchor, constant: 12), fineLabel.trailingAnchor.constraint(equalTo: finePanel.contentView.trailingAnchor, constant: -12)
        ])
    }

    func update(speedKmh: Int?, limit: Int?, alert: String?, fineText: String?) {
        speedLabel.text = speedKmh.map { "\($0) km/u" } ?? "-- km/u"
        limitLabel.text = limit.map { "limiet \($0)" } ?? "limiet --"
        alertLabel.text = alert ?? "Geen flitser in de buurt"
        alertLabel.textColor = alert == nil ? .systemGreen : .systemRed
        alertPanel.isHidden = alert == nil
        fineLabel.text = fineText ?? "Boete --"
        let noFine = fineText == "Boete —"
        fineLabel.textColor = noFine ? .white : .black
        finePanel.contentView.backgroundColor = (noFine ? UIColor.systemGray : UIColor.systemOrange).withAlphaComponent(0.88)
        finePanel.layer.zPosition = 50
        finePanel.isHidden = false
        view.bringSubviewToFront(finePanel)
    }

    func updateLaneSections(_ sections: [LaneSection]) {
        guard let section = sections.first, !section.lanes.isEmpty else {
            // Houd een duidelijke rechtdoorpijl zichtbaar wanneer de
            // routeprovider nog geen lane-metadata heeft.
            laneLabel.text = "↑"
            lanePanel.isHidden = false
            return
        }
        let laneText = NSMutableAttributedString()
        for (index, lane) in section.lanes.enumerated() {
            let direction = lane.follow ?? lane.directions.first ?? "STRAIGHT"
            let arrow: String
            switch direction {
            case "LEFT", "SLIGHT_LEFT", "SHARP_LEFT": arrow = "↖"
            case "RIGHT", "SLIGHT_RIGHT", "SHARP_RIGHT": arrow = "↗"
            case "LEFT_U_TURN", "RIGHT_U_TURN": arrow = "↩"
            default: arrow = "↑"
            }
            if index > 0 {
                laneText.append(NSAttributedString(string: "   "))
            }
            laneText.append(NSAttributedString(
                string: arrow,
                attributes: [
                    .foregroundColor: lane.follow == nil ? UIColor.systemGray : UIColor.systemGreen,
                    .font: UIFont.systemFont(ofSize: 24, weight: lane.follow == nil ? .regular : .bold),
                ]
            ))
        }
        laneLabel.attributedText = laneText
        lanePanel.isHidden = false
    }

    func updateManeuver(instruction: String?, distanceText: String?, laneSections: [LaneSection]) {
        guard let instruction, !instruction.isEmpty else {
            maneuverPanel.isHidden = true
            lanePanel.isHidden = true
            return
        }
        let arrow = maneuverArrow(for: instruction)
        maneuverLabel.text = distanceText.map { "\(arrow)   \($0)" } ?? arrow
        maneuverPanel.isHidden = false
        updateLaneSections(laneSections)
    }

    private func maneuverArrow(for instruction: String) -> String {
        let text = instruction.lowercased()
        if text.contains("rotonde") || text.contains("roundabout") { return "↻" }
        if text.contains("keer") || text.contains("u-turn") { return "↩" }
        if text.contains("links") || text.contains("left") { return "←" }
        if text.contains("rechts") || text.contains("right") { return "→" }
        return "↑"
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
        let heading = location.course >= 0 ? location.course : mapView.camera.heading
        let camera = MKMapCamera(lookingAtCenter: location.coordinate, fromDistance: 650, pitch: 58, heading: heading)
        mapView.setCamera(camera, animated: true)
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
