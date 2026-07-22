import CoreLocation
import MapKit
import UIKit

final class CarPlayMapViewController: UIViewController, MKMapViewDelegate {
    let mapView = MKMapView()
    private let speedLabel = UILabel()
    private let limitLabel = UILabel()
    private let alertLabel = UILabel()
    private let fineLabel = UILabel()
    private var refreshTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.pointOfInterestFilter = .excludingAll
        view.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        configureOverlay()
        refreshOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshOverlay()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshOverlay() {
        let snapshot = SharedStore.load()
        let alertText = snapshot.alert.map { "\($0.icon) \($0.label) • \($0.distance_m) m" }
        update(
            speedKmh: snapshot.speedKmh,
            limit: snapshot.speedLimitKmh,
            alert: alertText,
            fineText: snapshot.fineText
        )
    }

    private func configureOverlay() {
        let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.layer.cornerRadius = 12
        panel.clipsToBounds = true
        view.addSubview(panel)

        speedLabel.textColor = .white
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 26, weight: .bold)
        speedLabel.text = "--"
        limitLabel.textColor = .systemYellow
        limitLabel.font = .systemFont(ofSize: 14, weight: .bold)
        alertLabel.textColor = .systemGreen
        alertLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        alertLabel.numberOfLines = 2
        fineLabel.textColor = .white
        fineLabel.font = .systemFont(ofSize: 14, weight: .bold)
        fineLabel.numberOfLines = 2
        fineLabel.textAlignment = .center

        let speedStack = UIStackView(arrangedSubviews: [speedLabel, limitLabel])
        speedStack.axis = .horizontal
        speedStack.spacing = 8
        speedStack.alignment = .firstBaseline
        let stack = UIStackView(arrangedSubviews: [speedStack, alertLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(stack)
        let finePanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        finePanel.translatesAutoresizingMaskIntoConstraints = false
        finePanel.layer.cornerRadius = 12
        finePanel.clipsToBounds = true
        finePanel.contentView.addSubview(fineLabel)
        fineLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(finePanel)

        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            panel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 190),
            panel.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            stack.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -9),
            stack.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 11),
            stack.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -11),
            finePanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            finePanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            finePanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            fineLabel.topAnchor.constraint(equalTo: finePanel.contentView.topAnchor, constant: 8),
            fineLabel.bottomAnchor.constraint(equalTo: finePanel.contentView.bottomAnchor, constant: -8),
            fineLabel.leadingAnchor.constraint(equalTo: finePanel.contentView.leadingAnchor, constant: 12),
            fineLabel.trailingAnchor.constraint(equalTo: finePanel.contentView.trailingAnchor, constant: -12)
        ])
    }

    func update(speedKmh: Int?, limit: Int?, alert: String?, fineText: String?) {
        speedLabel.text = speedKmh.map { "\($0) km/u" } ?? "-- km/u"
        limitLabel.text = limit.map { "limiet \($0)" } ?? "limiet onbekend"
        alertLabel.text = alert ?? "Geen flitsmeldingen"
        alertLabel.textColor = alert == nil ? .systemGreen : .systemRed
        fineLabel.text = fineText.map { "🚨 \($0)" } ?? "Boete-indicatie actief bij overschrijding"
        fineLabel.textColor = fineText == nil ? .secondaryLabel : .systemRed
    }

    func showRoute(_ route: MKRoute) {
        mapView.removeOverlays(mapView.overlays)
        mapView.addOverlay(route.polyline)
        recenter()
    }

    func follow(location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 80 else { return }
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 650,
            longitudinalMeters: 650
        )
        mapView.setRegion(region, animated: true)
        mapView.userTrackingMode = .followWithHeading
    }

    func clearRoute() {
        mapView.removeOverlays(mapView.overlays)
    }

    func showNavigationError(_ message: String) {
        alertLabel.text = "⚠️ " + message
        alertLabel.textColor = .systemRed
    }

    func recenter() {
        mapView.userTrackingMode = .followWithHeading
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 6
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}
