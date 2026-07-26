import os
import unittest
from unittest.mock import Mock, patch

import app
import tomtom_traffic


class NavigationFeatureTests(unittest.TestCase):
    def setUp(self):
        app._speed_limit_cache.clear()
        app._camera_cache.clear()

    def test_speed_check_uses_tomtom_when_overpass_finds_no_road(self):
        with (
            patch.object(app, "run_overpass_query", return_value={"elements": []}),
            patch.object(app, "fetch_tomtom_speed_limit", return_value=100),
            patch.object(app, "fetch_flow_segment", return_value=None),
        ):
            response = app.app.test_client().get(
                "/api/speed-check?lat=52.0&lng=5.0&speed_kmh=113"
            )

        payload = response.get_json()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(payload["limit"]["maxspeed"], 100)
        self.assertEqual(payload["limit"]["source"], "tomtom_snap_to_roads")
        self.assertEqual(payload["fine"]["excess_kmh"], 9)
        self.assertEqual(payload["fine"]["bedrag"], 73)

    def test_lane_guidance_contains_coordinates_for_display_ordering(self):
        response = Mock()
        response.raise_for_status.return_value = None
        response.json.return_value = {
            "routes": [{
                "legs": [{
                    "points": [
                        {"latitude": 52.0, "longitude": 5.0},
                        {"latitude": 52.01, "longitude": 5.01},
                        {"latitude": 52.02, "longitude": 5.02},
                    ]
                }],
                "sections": [{
                    "sectionType": "LANES",
                    "startPointIndex": 1,
                    "endPointIndex": 2,
                    "lanes": [
                        {"directions": ["STRAIGHT"], "follow": "STRAIGHT"},
                        {"directions": ["RIGHT"]},
                    ],
                }],
            }]
        }

        with (
            patch.dict(os.environ, {"TOMTOM_API_KEY": "test-key"}),
            patch.object(tomtom_traffic.requests, "get", return_value=response),
        ):
            sections = tomtom_traffic.fetch_lane_guidance(52.0, 5.0, 52.02, 5.02)

        self.assertEqual(len(sections), 1)
        self.assertEqual(sections[0]["start_lat"], 52.01)
        self.assertEqual(sections[0]["start_lng"], 5.01)
        self.assertEqual(sections[0]["lanes"][0]["follow"], "STRAIGHT")

    def test_reports_include_fixed_cameras_for_the_map(self):
        camera = {
            "id": "osm-speed-camera-node-42",
            "type": "flitser_vast",
            "lat": 52.001,
            "lng": 5.001,
            "confirms": 0,
        }
        with (
            patch.object(app, "sync_ndw_reports"),
            patch.object(app, "fetch_osm_speed_cameras", return_value=[camera]),
            patch.object(app, "fetch_incidents", return_value=[]),
        ):
            response = app.app.test_client().get(
                "/api/reports?lat=52.0&lng=5.0&radius_km=5"
            )

        fixed = [
            report for report in response.get_json()["reports"]
            if report["type"] == "flitser_vast"
        ]
        self.assertTrue(any(report["id"] == camera["id"] for report in fixed))


if __name__ == "__main__":
    unittest.main()
