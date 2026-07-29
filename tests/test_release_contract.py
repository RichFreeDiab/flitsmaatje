from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
FASTFILE = (ROOT / "ios" / "fastlane" / "Fastfile").read_text(encoding="utf-8")


class TestFlightReleaseContractTests(unittest.TestCase):
    def test_release_waits_for_apple_processing_and_distributes_internally(self):
        self.assertIn("skip_waiting_for_build_processing: false", FASTFILE)
        self.assertIn("distribute_external: false", FASTFILE)
        self.assertIn("wait_processing_interval: 30", FASTFILE)
        self.assertIn("wait_processing_timeout_duration: 1800", FASTFILE)
        self.assertNotIn("skip_waiting_for_build_processing: true", FASTFILE)


if __name__ == "__main__":
    unittest.main()
