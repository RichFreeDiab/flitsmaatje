from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
COORDINATOR = (
    ROOT / "ios" / "FlitsMaatje" / "CarPlayNavigationCoordinator.swift"
).read_text(encoding="utf-8")
MAP_VIEW = (
    ROOT / "ios" / "FlitsMaatje" / "CarPlayMapViewController.swift"
).read_text(encoding="utf-8")
NAVIGATION = (
    ROOT / "ios" / "FlitsMaatje" / "NavigationService.swift"
).read_text(encoding="utf-8")
NAVIGATION_MAP = (
    ROOT / "ios" / "FlitsMaatje" / "NavigationMapView.swift"
).read_text(encoding="utf-8")


class CarPlayUIContractTests(unittest.TestCase):
    def test_maneuver_card_uses_guidance_detail_and_neutral_background(self):
        self.assertIn("let variants = instructionVariants(for: instruction)", COORDINATOR)
        self.assertIn("maneuver.instructionVariants = variants", COORDINATOR)
        self.assertIn("maneuver.cardBackgroundColor = .black", COORDINATOR)
        self.assertIn("Volg de route", COORDINATOR)
        self.assertIn("guidanceDetailText", COORDINATOR)
        self.assertNotIn("var variants = [instruction]", COORDINATOR)
        self.assertNotIn("Kies de gemarkeerde rijstrook", COORDINATOR)

    def test_navigation_service_is_shared_between_phone_and_carplay(self):
        self.assertIn("static let shared = NavigationService()", NAVIGATION)
        self.assertIn("NavigationService.shared", (
            ROOT / "ios" / "FlitsMaatje" / "LaunchView.swift"
        ).read_text(encoding="utf-8"))
        self.assertIn("NavigationService.shared", (
            ROOT / "ios" / "FlitsMaatje" / "CarPlaySceneDelegate.swift"
        ).read_text(encoding="utf-8"))
        self.assertNotIn("stopNavigation()", (
            ROOT / "ios" / "FlitsMaatje" / "CarPlaySceneDelegate.swift"
        ).read_text(encoding="utf-8"))

    def test_lane_choice_is_visual_arrows_with_exit_and_lane_detail_text(self):
        self.assertIn("googleMapsLaneStrip", NAVIGATION_MAP)
        self.assertIn("currentOrUpcomingExitBannerText", NAVIGATION_MAP)
        self.assertIn("Color.white", NAVIGATION_MAP)
        self.assertNotIn("recommendedLaneText", NAVIGATION_MAP)
        self.assertIn("guidanceDetailText", NAVIGATION)
        self.assertIn("shouldShowLaneSection", NAVIGATION)
        self.assertIn("flitsmeisterLaneStripText", MAP_VIEW)
        self.assertIn("formatExitBanner", NAVIGATION)

    def test_waypoints_are_not_double_encoded(self):
        api = (ROOT / "ios" / "Shared" / "FlitsMaatjeAPI.swift").read_text(encoding="utf-8")
        self.assertIn('URLQueryItem(name: "waypoints", value: json)', api)
        self.assertNotIn("addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)", api)

    def test_carplay_speed_refresh_does_not_hide_lane_panel(self):
        # Regression: update(speed...) used to force lanePanel.isHidden = true every second.
        update_fn = MAP_VIEW.split("func update(speedKmh:")[1].split("func compactFineText")[0]
        self.assertNotIn("lanePanel.isHidden = true", update_fn)
        self.assertNotIn("maneuverPanel.isHidden = true", update_fn)

    def test_should_show_lane_ignores_mapkit_step_length(self):
        self.assertIn("nooit MapKit-staplengte", NAVIGATION)
        self.assertNotIn("currentManeuverDistanceM <= Self.laneDisplayHorizonM", NAVIGATION)

    def test_lane_guidance_uses_official_carplay_metadata(self):
        self.assertIn("session.currentLaneGuidance = guidance", COORDINATOR)
        self.assertIn("maneuvers.first?.linkedLaneGuidance = guidance", COORDINATOR)
        self.assertIn("CPLane(", COORDINATOR)

    def test_lane_guidance_is_stable_and_kept_at_the_junction(self):
        self.assertIn("laneGuidanceLastSeenAt", COORDINATOR)
        self.assertIn("createdNewGuidance || session.currentLaneGuidance == nil", COORDINATOR)
        self.assertIn("Date().timeIntervalSince(laneGuidanceLastSeenAt) > 2.5", COORDINATOR)
        self.assertNotIn("return location.distance(from: end) <= 60", NAVIGATION)
        self.assertIn("isBehindVehicle(coordinate, from: location)", NAVIGATION)

    def test_alerts_do_not_replace_the_native_maneuver_card(self):
        self.assertNotIn("present(navigationAlert:", COORDINATOR)
        self.assertIn("De compacte flitserkaart staat rechtsonder", COORDINATOR)

    def test_map_follows_from_a_close_pitched_camera(self):
        self.assertIn("pitch: 64", MAP_VIEW)
        self.assertIn("let lookAhead =", MAP_VIEW)
        self.assertIn("maxCenterCoordinateDistance: 900", MAP_VIEW)

    def test_fine_card_contains_speed_and_compact_amount(self):
        self.assertIn('Boete bij \\($0) km/u:', MAP_VIEW)
        self.assertIn('return "\\(prefix)€ \\(amount)"', MAP_VIEW)

    def test_spoken_guidance_and_live_maneuver_distance_are_updated(self):
        self.assertIn("@Published var voiceEnabled: Bool", NAVIGATION)
        self.assertIn('speechPreferenceKey = "spoken-guidance-enabled"', NAVIGATION)
        self.assertIn('Toggle("Gesproken waarschuwingen"', NAVIGATION_MAP)
        self.assertIn("updateCurrentManeuverDistance(location: location", NAVIGATION)
        self.assertIn("speakCurrentStepIfNeeded()", NAVIGATION)

    def test_speed_limit_ignores_out_of_order_responses_and_refreshes_stale_data(self):
        location_service = (
            ROOT / "ios" / "FlitsMaatje" / "LocationBackgroundService.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("generation == speedCheckGeneration", location_service)
        self.assertIn("!isSpeedCheckInFlight, shouldRunSpeedCheck", location_service)
        self.assertIn("now.timeIntervalSince(lastSpeedLimitUpdatedAt) >= 5", location_service)

    def test_zero_gps_speed_uses_coordinate_fallback_and_fine_stays_visible_while_loading(self):
        location_service = (
            ROOT / "ios" / "FlitsMaatje" / "LocationBackgroundService.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("location.speed <= 0.5, coordinateSpeed >= 1.5", location_service)
        self.assertIn("FineCalculator.estimate(", location_service)
        self.assertNotIn('return "Boete wordt berekend…"', location_service)

    def test_native_maneuver_objects_are_stable_between_gps_updates(self):
        self.assertIn("private var stableManeuvers: [CPManeuver]", COORDINATOR)
        self.assertIn("let mustRebuild =", COORDINATOR)
        self.assertIn("session.updateEstimates(estimates, for: current)", COORDINATOR)
        self.assertEqual(COORDINATOR.count("session.upcomingManeuvers ="), 1)


if __name__ == "__main__":
    unittest.main()
