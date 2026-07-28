import unittest

from scripts.carplay_selftest import CarPlaySimulator


class CarPlaySelftestTests(unittest.TestCase):
    def test_handle_speeding_accepts_numeric_fine_payload(self):
        sim = CarPlaySimulator()
        sim.set_carplay_app("flitsmeister")

        shown = sim.handle_speeding(112, 100, 180)

        self.assertTrue(shown)
        self.assertIn("€180", sim.carplay_events[-1])

    def test_handle_speeding_skips_banner_when_excess_is_below_threshold(self):
        sim = CarPlaySimulator()
        sim.set_carplay_app("flitsmeister")

        shown = sim.handle_speeding(103, 100, 0)

        self.assertFalse(shown)
        self.assertEqual(sim.carplay_events, [])


if __name__ == "__main__":
    unittest.main()
