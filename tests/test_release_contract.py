from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
FASTFILE = (ROOT / "ios" / "fastlane" / "Fastfile").read_text(encoding="utf-8")
IOS_VERIFY = (ROOT / ".github" / "workflows" / "ios-verify.yml").read_text(encoding="utf-8")
EXISTING_BUILD_WORKFLOW = (
    ROOT / ".github" / "workflows" / "testflight_distribute_existing.yml"
).read_text(encoding="utf-8")


class TestFlightReleaseContractTests(unittest.TestCase):
    def test_release_waits_for_apple_processing_and_distributes_internally(self):
        self.assertIn("skip_waiting_for_build_processing: false", FASTFILE)
        self.assertIn("distribute_external: false", FASTFILE)
        self.assertIn("wait_processing_interval: 30", FASTFILE)
        self.assertIn("wait_processing_timeout_duration: 7200", FASTFILE)
        self.assertNotIn("skip_waiting_for_build_processing: true", FASTFILE)

    def test_existing_build_can_be_distributed_without_uploading_again(self):
        self.assertIn("lane :distribute_existing do", FASTFILE)
        self.assertIn("app_identifier: APP_BUNDLE_ID", FASTFILE)
        self.assertIn('app_platform: "ios"', FASTFILE)
        self.assertIn("distribute_only: true", FASTFILE)
        self.assertIn('ENV.fetch("TESTFLIGHT_BUILD_NUMBER")', FASTFILE)
        self.assertIn("bundle exec fastlane distribute_existing", EXISTING_BUILD_WORKFLOW)

    def test_release_jobs_outlive_apple_processing_window(self):
        self.assertIn("timeout-minutes: 150", IOS_VERIFY)
        self.assertIn("timeout-minutes: 150", EXISTING_BUILD_WORKFLOW)


if __name__ == "__main__":
    unittest.main()
