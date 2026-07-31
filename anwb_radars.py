"""Actuele mobiele snelheidscontroles uit de ANWB-verkeersfeed.

Deze koppeling is bedoeld voor de persoonlijke FlitsMaatje-installatie. De
feed is een interne webfeed (geen gegarandeerde publieke ontwikkelaars-API),
daarom pollen we zuinig en houden we kort een noodcache vast bij een storing.
"""

import math
import threading
import time

import requests


ANWB_INCIDENTS_URL = (
    "https://api.anwb.nl/traffic/traffic-info/v1/incidents/incidents-desktop"
)
ANWB_CACHE_TTL = 120
ANWB_STALE_TTL = 15 * 60
ANWB_TIMEOUT = (2, 5)

_cache_lock = threading.Lock()
_cached_radars = []
_last_attempt = 0.0
_last_success = 0.0


def _bearing_degrees(start, end):
    """Bereken de rijrichting vanaf de segmentpunten in graden."""
    if not isinstance(start, dict) or not isinstance(end, dict):
        return None
    try:
        lat1 = math.radians(float(start["lat"]))
        lat2 = math.radians(float(end["lat"]))
        delta_lng = math.radians(float(end["lon"]) - float(start["lon"]))
    except (KeyError, TypeError, ValueError):
        return None

    y = math.sin(delta_lng) * math.cos(lat2)
    x = (
        math.cos(lat1) * math.sin(lat2)
        - math.sin(lat1) * math.cos(lat2) * math.cos(delta_lng)
    )
    return round((math.degrees(math.atan2(y, x)) + 360) % 360, 1)


def _parse_radars(payload, now):
    reports = []
    seen = set()
    for road in payload.get("roads") or []:
        for segment in road.get("segments") or []:
            for radar in segment.get("radars") or []:
                location = radar.get("loc") or {}
                try:
                    radar_id = str(radar["id"])
                    lat = float(location["lat"])
                    lng = float(location["lon"])
                except (KeyError, TypeError, ValueError):
                    continue
                if radar_id in seen or not (-90 <= lat <= 90 and -180 <= lng <= 180):
                    continue
                seen.add(radar_id)
                reports.append({
                    "id": f"anwb-radar-{radar_id}",
                    "type": "flitser_mobiel",
                    "lat": lat,
                    "lng": lng,
                    "heading": _bearing_degrees(radar.get("fromLoc"), radar.get("toLoc")),
                    "confirms": 1,
                    "created_at": now,
                    "expires_at": now + ANWB_STALE_TTL,
                    "road": radar.get("road") or road.get("road"),
                    "hectometer": radar.get("HM"),
                    "source": "ANWB",
                })
    return reports


def fetch_anwb_mobile_radars(force=False):
    """Geef de actuele mobiele controles, met twee minuten request-cache."""
    global _cached_radars, _last_attempt, _last_success
    now = time.time()
    with _cache_lock:
        if not force and now - _last_attempt < ANWB_CACHE_TTL:
            return list(_cached_radars) if now - _last_success <= ANWB_STALE_TTL else []
        _last_attempt = now

        try:
            response = requests.get(
                ANWB_INCIDENTS_URL,
                timeout=ANWB_TIMEOUT,
                headers={
                    "User-Agent": "FlitsMaatje/1.1 (personal-use)",
                    "Accept": "application/json",
                },
            )
            response.raise_for_status()
            payload = response.json()
            if payload.get("success") is not True:
                raise ValueError("ANWB-feed meldt geen succes")
            _cached_radars = _parse_radars(payload, now)
            _last_success = now
        except Exception:
            if now - _last_success > ANWB_STALE_TTL:
                _cached_radars = []

        return list(_cached_radars)
