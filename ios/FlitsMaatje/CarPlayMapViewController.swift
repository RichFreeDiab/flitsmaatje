import MapKit
import UIKit

final class CarPlayMapViewController: UIViewController, MKMapViewDelegate {
    let mapView = MKMapView()
    private let speedLabel = UILabel()
    private let alertLabel = UILabel()
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
        let alertText = snapshot.alert.map { "\($0.icon) \($0.label) — over \($0.distance_m) m" }
        update(speedKmh: snapshot.speedKmh, limit: snapshot.speedLimitKmh, alert: alertText ?? snapshot.fineText)
    }

    private func configureOverlay() {
        let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.layer.cornerRadius = 14
        panel.clipsToBounds = true
        view.addSubview(panel)

        speedLabel.textColor = .white
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        speedLabel.text = "-- km/u"
        alertLabel.textColor = .systemGreen
        alertLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        alertLabel.numberOfLines = 2
        let stack = UIStackView(arrangedSubviews: [speedLabel, alertLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            panel.widthAnchor.constraint(equalToConstant: 240),
            stack.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -14)
        ])
    }

    func update(speedKmh: Int?, limit: Int?, alert: String?) {
        let speed = speedKmh.map(String.init) ?? "--"
        let limitText = limit.map { "  limiet \($0)" } ?? ""
        speedLabel.text = "\(speed) km/u\(limitText)"
        alertLabel.text = alert ?? "Geen flitsmeldingen"
        alertLabel.textColor = alert == nil ? .systemGreen : .systemRed
    }

    func showRoute(_ route: MKRoute) {
        mapView.removeOverlays(mapView.overlays)
        mapView.addOverlay(route.polyline)
        mapView.setVisibleMapRect(
            route.polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 120, right: 40),
            animated: true
        )
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
