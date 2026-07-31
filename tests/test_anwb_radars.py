import unittest
from unittest.mock import Mock, patch

import anwb_radars


class ANWBRadarTests(unittest.TestCase):
    def setUp(self):
        anwb_radars._cached_radars = []
        anwb_radars._last_attempt = 0.0
        anwb_radars._last_success = 0.0

    def test_fetches_exact_mobile_radar_location_and_direction(self):
        response = Mock()
        response.raise_for_status.return_value = None
        response.json.return_value = {
            "success": True,
            "roads": [{
                "road": "A2",
                "segments": [{
                    "radars": [{
                        "id": 4174379211,
                        "road": "A2",
                        "HM": 81.0,
                        "fromLoc": {"lat": 51.90089, "lon": 5.18821},
                        "toLoc": {"lat": 51.9427, "lon": 5.14571},
                        "loc": {"lat": 51.93157, "lon": 5.16207},
                    }]
                }],
            }],
        }

        with patch.object(anwb_radars.requests, "get", return_value=response) as get:
            reports = anwb_radars.fetch_anwb_mobile_radars(force=True)

        self.assertEqual(len(reports), 1)
        self.assertEqual(reports[0]["id"], "anwb-radar-4174379211")
        self.assertEqual(reports[0]["type"], "flitser_mobiel")
        self.assertEqual(reports[0]["lat"], 51.93157)
        self.assertEqual(reports[0]["lng"], 5.16207)
        self.assertTrue(320 <= reports[0]["heading"] <= 340)
        self.assertEqual(reports[0]["hectometer"], 81.0)
        self.assertEqual(get.call_count, 1)

    def test_keeps_last_success_briefly_when_feed_fails(self):
        anwb_radars._cached_radars = [{"id": "anwb-radar-cached"}]
        anwb_radars._last_success = 990.0
        with (
            patch.object(anwb_radars.time, "time", return_value=1000.0),
            patch.object(anwb_radars.requests, "get", side_effect=TimeoutError),
        ):
            reports = anwb_radars.fetch_anwb_mobile_radars(force=True)

        self.assertEqual(reports[0]["id"], "anwb-radar-cached")


if __name__ == "__main__":
    unittest.main()
