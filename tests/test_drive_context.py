"""Tests for corridor matching, ranking and drive-context API."""

import unittest
from unittest.mock import patch

import app
import drive_context


class DriveContextTests(unittest.TestCase):
    def setUp(self):
        self.anwb_patch = patch.object(app, "fetch_anwb_mobile_radars", return_value=[])
        self.anwb_patch.start()
        self.addCleanup(self.anwb_patch.stop)
        self.inc_patch = patch.object(app, "fetch_incidents", return_value=[])
        self.inc_patch.start()
        self.addCleanup(self.inc_patch.stop)
        self.ndw_patch = patch.object(app, "sync_ndw_reports")
        self.ndw_patch.start()
        self.addCleanup(self.ndw_patch.stop)
        self.osm_patch = patch.object(app, "fetch_osm_speed_cameras", return_value=[])
        self.osm_patch.start()
        self.addCleanup(self.osm_patch.stop)
        self.should_osm = patch.object(app, "should_fetch_osm_speed_cameras", return_value=False)
        self.should_osm.start()
        self.addCleanup(self.should_osm.stop)

    def test_parse_route_and_corridor_distance(self):
        points = drive_context.parse_route_points("52.10000,5.10000;52.20000,5.20000")
        self.assertEqual(len(points), 2)
        # Point on the opposite parallel offset should be farther than on-route.
        on_route = drive_context.distance_to_corridor_m(52.15, 5.15, points)
        off_route = drive_context.distance_to_corridor_m(52.15, 5.18, points)
        self.assertLess(on_route, 5)
        self.assertGreater(off_route, 40)

    def test_ranking_prefers_anwb_mobile_over_far_fixed(self):
        fixed = drive_context.enrich_candidate(
            {"id": "osm-1", "type": "flitser_vast", "lat": 52.101, "lng": 5.101, "confirms": 1, "source": "osm"},
            52.10, 5.10,
        )
        mobile = drive_context.enrich_candidate(
            {"id": "anwb-1", "type": "flitser_mobiel", "lat": 52.102, "lng": 5.102, "confirms": 1, "source": "anwb", "road": "A27", "hectometer": "42.1"},
            52.10, 5.10,
        )
        best = drive_context.select_ranked_alert(
            [fixed, mobile],
            app.WARN_DISTANCE_M,
            heading_matches_fn=app.heading_matches,
        )
        self.assertEqual(best["id"], "anwb-1")
        payload = drive_context.serialize_alert(best, app.TYPE_LABELS, app.TYPE_ICONS)
        self.assertEqual(payload["road_ref"], "A27")
        self.assertEqual(payload["alert_kind"], "mobile")

    def test_corridor_filters_opposite_carriageway(self):
        route = drive_context.parse_route_points("52.1000,5.1000;52.1100,5.1000")
        opposite = drive_context.enrich_candidate(
            {
                "id": "cam-opp",
                "type": "flitser_vast",
                "lat": 52.1050,
                "lng": 5.1018,  # ~120m east of northbound corridor
                "heading": 180,
                "confirms": 1,
                "source": "osm",
            },
            52.1010,
            5.1000,
            user_heading=0,
            route_points=route,
        )
        on_route = drive_context.enrich_candidate(
            {
                "id": "cam-on",
                "type": "flitser_vast",
                "lat": 52.1050,
                "lng": 5.1000,
                "heading": 0,
                "confirms": 1,
                "source": "osm",
            },
            52.1010,
            5.1000,
            user_heading=0,
            route_points=route,
        )
        best = drive_context.select_ranked_alert(
            [opposite, on_route],
            app.WARN_DISTANCE_M,
            user_heading=0,
            route_points=route,
            heading_matches_fn=app.heading_matches,
        )
        self.assertIsNotNone(best)
        self.assertEqual(best["id"], "cam-on")

    def test_drive_context_endpoint_shape(self):
        camera = {
            "id": "osm-speed-camera-node-1",
            "type": "flitser_vast",
            "lat": 52.001,
            "lng": 5.001,
            "heading": 90,
            "confirms": 1,
            "source": "osm",
        }
        with (
            patch.object(app, "should_fetch_osm_speed_cameras", return_value=True),
            patch.object(app, "fetch_osm_speed_cameras", return_value=[camera]),
        ):
            response = app.app.test_client().get(
                "/api/drive-context?lat=52.0&lng=5.0&radius_km=5&heading=90"
            )
        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertIn("speed_traps", payload)
        self.assertIn("speed_traps_alt", payload)
        self.assertIn("incidents", payload)
        self.assertIn("traffic_jams", payload)
        self.assertIn("early", payload)
        self.assertTrue(payload["meta"]["ranked"])

    def test_early_warnings_skips_fixed_cameras(self):
        fixed = {
            "id": "osm-fixed",
            "type": "flitser_vast",
            "lat": 52.001,
            "lng": 5.001,
            "confirms": 1,
            "source": "osm",
        }
        mobile = {
            "id": "anwb-radar-9",
            "type": "flitser_mobiel",
            "lat": 52.002,
            "lng": 5.002,
            "confirms": 1,
            "source": "anwb",
            "road": "A6",
            "hectometer": "12.3",
        }
        with (
            patch.object(app, "fetch_osm_speed_cameras", return_value=[fixed]),
            patch.object(app, "should_fetch_osm_speed_cameras", return_value=True),
            patch.object(app, "fetch_anwb_mobile_radars", return_value=[mobile]),
        ):
            response = app.app.test_client().get(
                "/api/early-warnings?lat=52.0&lng=5.0&radius_km=5"
            )
        payload = response.get_json()
        ids = {a["id"] for a in payload["alerts"]}
        self.assertIn("anwb-radar-9", ids)
        self.assertNotIn("osm-fixed", ids)

    def test_lane_guidance_normalized_items(self):
        sections = [{
            "start_point_index": 0,
            "end_point_index": 1,
            "start_lat": 52.0,
            "start_lng": 5.0,
            "end_lat": 52.01,
            "end_lng": 5.01,
            "lanes": [
                {"directions": ["LEFT"], "follow": None},
                {"directions": ["STRAIGHT"], "follow": "STRAIGHT"},
            ],
        }]
        with patch.object(app, "fetch_lane_guidance", return_value=sections):
            response = app.app.test_client().get(
                "/api/lane-guidance?origin_lat=52&origin_lng=5&destination_lat=52.1&destination_lng=5.1"
            )
        payload = response.get_json()
        items = payload["sections"][0]["items"]
        self.assertEqual(items[0]["directionType"], "left")
        self.assertFalse(items[0]["isActive"])
        self.assertEqual(items[1]["directionType"], "straight")
        self.assertTrue(items[1]["isActive"])


if __name__ == "__main__":
    unittest.main()
