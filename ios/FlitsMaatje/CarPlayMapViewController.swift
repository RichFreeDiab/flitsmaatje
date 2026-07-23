import CoreLocation
import MapKit
import UIKit

final class CarPlayMapViewController: UIViewController, MKMapViewDelegate {
    let mapView = MKMapView()
    private let speedLabel = UILabel()
    private let limitLabel = UILabel()
    private let alertLabel = UILabel()
    private let fineLabel = UILabel()
    private let alertPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let finePanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private var refreshTimer: Timer?

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
        fineLabel.font = .systemFont(ofSize: 16, weight: .bold); fineLabel.numberOfLines = 3; fineLabel.textAlignment = .center; fineLabel.adjustsFontSizeToFitWidth = true; fineLabel.minimumScaleFactor = 0.82

        let speedStack = UIStackView(arrangedSubviews: [speedLabel, limitLabel]); speedStack.axis = .horizontal; speedStack.spacing = 8; speedStack.alignment = .firstBaseline
        speedStack.translatesAutoresizingMaskIntoConstraints = false; statusPanel.contentView.addSubview(speedStack)

        [alertPanel, finePanel].forEach { panel in panel.translatesAutoresizingMaskIntoConstraints = false; panel.layer.cornerRadius = 12; panel.clipsToBounds = true; view.addSubview(panel) }
        alertLabel.translatesAutoresizingMaskIntoConstraints = false; fineLabel.translatesAutoresizingMaskIntoConstraints = false
        alertPanel.contentView.addSubview(alertLabel); finePanel.contentView.addSubview(fineLabel)

        NSLayoutConstraint.activate([
            statusPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12), statusPanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            speedStack.topAnchor.constraint(equalTo: statusPanel.contentView.topAnchor, constant: 9), speedStack.bottomAnchor.constraint(equalTo: statusPanel.contentView.bottomAnchor, constant: -9), speedStack.leadingAnchor.constraint(equalTo: statusPanel.contentView.leadingAnchor, constant: 11), speedStack.trailingAnchor.constraint(equalTo: statusPanel.contentView.trailingAnchor, constant: -11),
            alertPanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18), alertPanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18), alertPanel.bottomAnchor.constraint(equalTo: finePanel.topAnchor, constant: -8),
            alertLabel.topAnchor.constraint(equalTo: alertPanel.contentView.topAnchor, constant: 10), alertLabel.bottomAnchor.constraint(equalTo: alertPanel.contentView.bottomAnchor, constant: -10), alertLabel.leadingAnchor.constraint(equalTo: alertPanel.contentView.leadingAnchor, constant: 12), alertLabel.trailingAnchor.constraint(equalTo: alertPanel.contentView.trailingAnchor, constant: -12),
            finePanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18), finePanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18), finePanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            fineLabel.topAnchor.constraint(equalTo: finePanel.contentView.topAnchor, constant: 10), fineLabel.bottomAnchor.constraint(equalTo: finePanel.contentView.bottomAnchor, constant: -10), fineLabel.leadingAnchor.constraint(equalTo: finePanel.contentView.leadingAnchor, constant: 12), fineLabel.trailingAnchor.constraint(equalTo: finePanel.contentView.trailingAnchor, constant: -12)
        ])
    }

    func update(speedKmh: Int?, limit: Int?, alert: String?, fineText: String?) {
        speedLabel.text = speedKmh.map { "\($0) km/u" } ?? "-- km/u"
        limitLabel.text = limit.map { "limiet \($0)" } ?? "limiet --"
        alertLabel.text = alert ?? "Geen flitser in de buurt"
        alertLabel.textColor = alert == nil ? .systemGreen : .systemRed
        alertPanel.isHidden = alert == nil
        fineLabel.text = fineText.map { "🚨 BOETE-INDICATIE  •  \($0)" } ?? ""
        fineLabel.textColor = .systemRed
        finePanel.isHidden = fineText == nil
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
}