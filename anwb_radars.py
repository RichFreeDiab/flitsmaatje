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
ANWB_HEADERS = {
    "User-Agent": "FlitsMaatje/1.1 (personal-use; +https://flitsmaatje.readvanes.nl)",
    "Accept": "application/json",
    "Accept-Language": "nl-NL,nl;q=0.9",
}

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


def _radar_location(radar):
    location = radar.get("loc") or {}
    try:
        lat = float(location["lat"])
        lng = float(location["lon"])
        return lat, lng
    except (KeyError, TypeError, ValueError):
        pass
    start = radar.get("fromLoc") or {}
    end = radar.get("toLoc") or {}
    try:
        lat = (float(start["lat"]) + float(end["lat"])) / 2
        lng = (float(start["lon"]) + float(end["lon"])) / 2
        return lat, lng
    except (KeyError, TypeError, ValueError):
        return None


def _iter_radar_records(payload):
    """Radars staan meestal op segmenten; soms ook op de weg zelf."""
    for road in payload.get("roads") or []:
        for radar in road.get("radars") or []:
            yield road, radar
        for segment in road.get("segments") or []:
            for radar in segment.get("radars") or []:
                yield road, radar
            for item in segment.get("incidents") or []:
                kind = str(item.get("incidentType") or item.get("category") or "").lower()
                if kind in {"radar", "radars"}:
                    yield road, item
    for warning in payload.get("warnings") or []:
        kind = str(warning.get("incidentType") or warning.get("category") or "").lower()
        if kind in {"radar", "radars"}:
            yield {}, warning


def _parse_radars(payload, now):
    reports = []
    seen = set()
    for road, radar in _iter_radar_records(payload):
        coords = _radar_location(radar)
        try:
            radar_id = str(radar["id"])
        except (KeyError, TypeError):
            continue
        if not coords:
            continue
        lat, lng = coords
        if radar_id in seen or not (-90 <= lat <= 90 and -180 <= lng <= 180):
            continue
        seen.add(radar_id)
        events = radar.get("events") or []
        event_text = ""
        if events and isinstance(events[0], dict):
            event_text = str(events[0].get("text") or "")
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
            "description": event_text or radar.get("reason"),
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
                headers=ANWB_HEADERS,
            )
            response.raise_for_status()
            payload = response.json()
            if payload.get("success") is False:
                raise ValueError("ANWB-feed meldt geen succes")
            if not isinstance(payload.get("roads"), list) and payload.get("success") is not True:
                raise ValueError("ANWB-feed mist wegen")
            _cached_radars = _parse_radars(payload, now)
            _last_success = now
        except Exception:
            if now - _last_success > ANWB_STALE_TTL:
                _cached_radars = []

        return list(_cached_radars)
