import os
import unittest
from unittest.mock import Mock, patch

import app
import tomtom_traffic


class NavigationFeatureTests(unittest.TestCase):
    def setUp(self):
        app._speed_limit_cache.clear()
        app._camera_cache.clear()
        self.anwb_patch = patch.object(app, "fetch_anwb_mobile_radars", return_value=[])
        self.anwb_patch.start()
        self.addCleanup(self.anwb_patch.stop)

    def test_speed_check_uses_fast_tomtom_path_without_waiting_for_overpass(self):
        with (
            patch.object(app, "run_overpass_query", return_value={"elements": []}) as overpass,
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
        overpass.assert_not_called()

    def test_tomtom_speed_limit_uses_two_points_and_parses_route_segments(self):
        response = Mock()
        response.raise_for_status.return_value = None
        response.json.return_value = {
            "route": [{
                "properties": {
                    "speedLimits": {"value": 30, "unit": "kmph"}
                }
            }]
        }
        with (
            patch.dict(os.environ, {"TOMTOM_API_KEY": "test-key"}),
            patch.object(tomtom_traffic.requests, "get", return_value=response) as request,
        ):
            limit = tomtom_traffic.fetch_tomtom_speed_limit(52.3676, 4.9041)

        self.assertEqual(limit, 30)
        points = request.call_args.kwargs["params"]["points"]
        self.assertEqual(len(points.split(";")), 2)

    def test_reports_preserve_fixed_camera_heading(self):
        camera = {
            "id": "osm-speed-camera-node-99",
            "type": "flitser_vast",
            "lat": 52.001,
            "lng": 5.001,
            "heading": 180,
            "confirms": 0,
        }
        with (
            patch.dict(os.environ, {"FLITSMAATJE_ENABLE_OSM_CAMERAS": "1"}),
            patch.object(app, "sync_ndw_reports"),
            patch.object(app, "fetch_osm_speed_cameras", return_value=[camera]),
            patch.object(app, "fetch_incidents", return_value=[]),
        ):
            response = app.app.test_client().get(
                "/api/reports?lat=52.0&lng=5.0&radius_km=5"
            )

        fixed = next(
            report for report in response.get_json()["reports"]
            if report["id"] == camera["id"]
        )
        self.assertEqual(fixed["heading"], 180)


    def test_fine_estimate_requires_a_known_limit(self):
        self.assertIsNone(app.estimate_fine("snelweg", 113, None))

    def test_nearby_alert_excludes_opposite_direction_fixed_camera(self):
        camera = {
            "id": "osm-speed-camera-node-opposite",
            "type": "flitser_vast",
            "lat": 52.0005,
            "lng": 5.0005,
            "heading": 180,
            "confirms": 0,
        }
        with (
            patch.dict(os.environ, {"FLITSMAATJE_ENABLE_OSM_CAMERAS": "1"}),
            patch.object(app, "sync_ndw_reports"),
            patch.object(app, "fetch_osm_speed_cameras", return_value=[camera]),
            patch.object(app, "fetch_incidents", return_value=[]),
        ):
            response = app.app.test_client().get(
                "/api/nearby-alert?lat=52.0&lng=5.0&heading=0"
            )

        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.get_json()["alert"])


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
            patch.dict(os.environ, {"FLITSMAATJE_ENABLE_OSM_CAMERAS": "1"}),
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

    def test_database_region_does_not_wait_for_live_osm(self):
        with (
            patch.object(app, "sync_ndw_reports"),
            patch.object(app, "fetch_osm_speed_cameras") as osm,
            patch.object(app, "fetch_incidents", return_value=[]),
        ):
            response = app.app.test_client().get(
                "/api/reports?lat=52.3676&lng=4.9041&radius_km=2"
            )

        self.assertEqual(response.status_code, 200)
        osm.assert_not_called()

    def test_cleanup_keeps_fixed_camera_source_data(self):
        with app.app.app_context():
            db = app.get_db()
            camera_id = "test-expired-fixed-camera"
            db.execute(
                "INSERT OR REPLACE INTO reports "
                "(id, type, lat, lng, heading, created_at, expires_at, confirms, denies) "
                "VALUES (?, 'flitser_vast', 52.0, 5.0, NULL, 0, 0, 1, 0)",
                (camera_id,),
            )
            db.commit()

            app.cleanup_expired(db)

            self.assertIsNotNone(
                db.execute("SELECT id FROM reports WHERE id = ?", (camera_id,)).fetchone()
            )
            db.execute("DELETE FROM reports WHERE id = ?", (camera_id,))
            db.commit()

    def test_anwb_mobile_radar_is_visible_and_triggers_nearby_alert(self):
        radar = {
            "id": "anwb-radar-123",
            "type": "flitser_mobiel",
            "lat": 52.0005,
            "lng": 5.0005,
            "heading": 0.0,
            "confirms": 1,
            "created_at": 100.0,
            "expires_at": 1000.0,
        }
        with (
            patch.object(app, "sync_ndw_reports"),
            patch.object(app, "fetch_anwb_mobile_radars", return_value=[radar]),
            patch.object(app, "fetch_incidents", return_value=[]),
        ):
            reports_response = app.app.test_client().get(
                "/api/reports?lat=52.0&lng=5.0&radius_km=2"
            )
            alert_response = app.app.test_client().get(
                "/api/nearby-alert?lat=52.0&lng=5.0&heading=0&radius_km=2"
            )

        reports = reports_response.get_json()["reports"]
        self.assertTrue(any(item["id"] == radar["id"] for item in reports))
        self.assertEqual(alert_response.get_json()["alert"]["id"], radar["id"])


if __name__ == "__main__":
    unittest.main()
