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
    def test_maneuver_card_uses_only_native_arrow_and_neutral_background(self):
        self.assertIn("let variants = instructionVariants()", COORDINATOR)
        self.assertIn("maneuver.instructionVariants = variants", COORDINATOR)
        self.assertIn("maneuver.cardBackgroundColor = .black", COORDINATOR)
        self.assertIn(r'["\u{00A0}"]', COORDINATOR)
        self.assertNotIn("var variants = [instruction]", COORDINATOR)

    def test_lane_guidance_uses_official_carplay_metadata(self):
        self.assertIn("session.currentLaneGuidance = guidance", COORDINATOR)
        self.assertIn("maneuvers.first?.linkedLaneGuidance = guidance", COORDINATOR)
        self.assertIn("CPLane(", COORDINATOR)

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
        self.assertIn('return "Boete wordt berekend…"', location_service)


if __name__ == "__main__":
    unittest.main()
