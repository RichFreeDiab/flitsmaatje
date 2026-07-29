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


class CarPlayUIContractTests(unittest.TestCase):
    def test_maneuver_card_uses_real_instruction_and_neutral_background(self):
        self.assertIn("let variants = instructionVariants(for: instruction)", COORDINATOR)
        self.assertIn("maneuver.instructionVariants = variants", COORDINATOR)
        self.assertIn("maneuver.cardBackgroundColor = .black", COORDINATOR)
        self.assertNotIn("maneuver.instructionVariants = [arrow]", COORDINATOR)

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
        self.assertIn("@Published var voiceEnabled = true", NAVIGATION)
        self.assertIn("updateCurrentManeuverDistance(location: location", NAVIGATION)
        self.assertIn("speakCurrentStepIfNeeded()", NAVIGATION)


if __name__ == "__main__":
    unittest.main()
