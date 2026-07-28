import unittest

import app


class NearbyAlertRowTests(unittest.TestCase):
    def test_nearby_alert_handles_sqlite_rows(self):
        client = app.app.test_client()
        create_response = client.post(
            "/api/reports",
            json={"type": "flitser_vast", "lat": 52.12345, "lng": 5.12345},
        )
        self.assertIn(create_response.status_code, (200, 201))

        response = client.get("/api/nearby-alert?lat=52.12345&lng=5.12345")
        payload = response.get_json()

        self.assertEqual(response.status_code, 200)
        self.assertIsNotNone(payload["alert"])
        self.assertIn("confirms", payload["alert"])


if __name__ == "__main__":
    unittest.main()
