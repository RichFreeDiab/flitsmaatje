import MapKit
import UIKit

final class CarPlayMapViewController: UIViewController, MKMapViewDelegate {
    let mapView = MKMapView()

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
