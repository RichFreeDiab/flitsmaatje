"""Server-side TomTom Traffic integration.

The API key is deliberately read only from TOMTOM_API_KEY. Never ship it in
the iOS app or commit it to the repository.
"""
import os
import threading
import time

import requests

TOMTOM_URL = "https://api.tomtom.com/traffic/services/4/flowSegmentData/absolute/10/json"
TOMTOM_INCIDENTS_URL = "https://api.tomtom.com/traffic/services/5/incidentDetails"
TOMTOM_SNAP_URL = "https://api.tomtom.com/snapToRoads/1/"
TOMTOM_ROUTING_URL = "https://api.tomtom.com/routing/1/calculateRoute"
_cache = {}
_cache_lock = threading.Lock()
_CACHE_MAX = 512


def _cached(key):
    now = time.monotonic()
    with _cache_lock:
        item = _cache.get(key)
        if item and item[0] > now:
            return True, item[1]
        if item:
            _cache.pop(key, None)
    return False, None


def _store(key, value, ttl):
    with _cache_lock:
        if len(_cache) >= _CACHE_MAX:
            oldest = min(_cache, key=lambda cache_key: _cache[cache_key][0])
            _cache.pop(oldest, None)
        _cache[key] = (time.monotonic() + ttl, value)


def fetch_lane_guidance(origin_lat, origin_lng, destination_lat, destination_lng):
    """Fetch TomTom v1 lane sections for the active route."""
    api_key = os.environ.get("TOMTOM_API_KEY")
    if not api_key:
        return []
    try:
        response = requests.get(
            f"{TOMTOM_ROUTING_URL}/{origin_lat},{origin_lng}:{destination_lat},{destination_lng}/json",
            params={
                "key": api_key,
                "traffic": "true",
                "routeType": "fastest",
                "travelMode": "car",
                "instructionsType": "text",
                "language": "nl-NL",
                "sectionType": "lanes",
                "instructionAnnouncementPoints": "all",
            },
            headers={"User-Agent": "FlitsMaatje/1.1"},
            timeout=8,
        )
        response.raise_for_status()
        routes = response.json().get("routes") or []
        if not routes:
            return []
        route = routes[0]
        sections = route.get("sections") or []
        route_points = []
        for leg in route.get("legs") or []:
            for point in leg.get("points") or []:
                if not route_points or point != route_points[-1]:
                    route_points.append(point)
        result = []
        for section in sections:
            if section.get("sectionType") != "LANES":
                continue
            lanes = []
            for lane in section.get("lanes") or []:
                directions = lane.get("directions") or []
                lanes.append({
                    "directions": directions,
                    "follow": lane.get("follow"),
                })
            if lanes:
                start_index = int(section.get("startPointIndex", 0))
                end_index = int(section.get("endPointIndex", start_index))
                start_point = route_points[start_index] if 0 <= start_index < len(route_points) else {}
                end_point = route_points[end_index] if 0 <= end_index < len(route_points) else {}
                result.append({
                    "start_point_index": start_index,
                    "end_point_index": end_index,
                    "start_lat": start_point.get("latitude"),
                    "start_lng": start_point.get("longitude"),
                    "end_lat": end_point.get("latitude"),
                    "end_lng": end_point.get("longitude"),
                    "lanes": lanes,
                })
        return result
    except (requests.RequestException, ValueError, TypeError, KeyError):
        return []


def fetch_tomtom_speed_limit(lat, lng):
    """Return the static speed limit from TomTom's road-matching service."""
    api_key = os.environ.get("TOMTOM_API_KEY")
    if not api_key:
        return None
    cache_key = ("limit", round(lat, 4), round(lng, 4))
    hit, cached = _cached(cache_key)
    if hit:
        return cached
    fields = "{route{properties{speedLimits{value,unit}}}}"
    try:
        response = requests.get(
            TOMTOM_SNAP_URL,
            params={
                "key": api_key,
                "points": f"{lng},{lat}",
                "fields": fields,
                "vehicleType": "PassengerCar",
                "measurementSystem": "metric",
                "offroadMargin": 50,
            },
            headers={"User-Agent": "FlitsMaatje/1.1"},
            timeout=5,
        )
        response.raise_for_status()
        route = response.json().get("route") or {}
        properties = route.get("properties") or {}
        limits = properties.get("speedLimits") or []
        for item in limits:
            value = item.get("value") if isinstance(item, dict) else None
            if value is not None:
                result = int(round(float(value)))
                _store(cache_key, result, 300)
                return result
    except (requests.RequestException, ValueError, TypeError, KeyError):
        _store(cache_key, None, 20)
        return None
    _store(cache_key, None, 20)
    return None


def fetch_flow_segment(lat, lng):
    api_key = os.environ.get("TOMTOM_API_KEY")
    if not api_key:
        return None
    cache_key = ("flow", round(lat, 3), round(lng, 3))
    hit, cached = _cached(cache_key)
    if hit:
        return cached

    try:
        response = requests.get(
            TOMTOM_URL,
            params={"key": api_key, "point": f"{lat},{lng}", "unit": "kmph"},
            headers={"User-Agent": "FlitsMaatje/1.1"},
            timeout=5,
        )
        response.raise_for_status()
        data = response.json().get("flowSegmentData", {})
        current = data.get("currentSpeed")
        free_flow = data.get("freeFlowSpeed")
        travel_time = data.get("currentTravelTime")
        free_flow_time = data.get("freeFlowTravelTime")
        delay = None
        if travel_time is not None and free_flow_time is not None:
            delay = max(0, int(travel_time) - int(free_flow_time))
        result = {
            "current_speed_kmh": current,
            "free_flow_speed_kmh": free_flow,
            "current_travel_time_s": travel_time,
            "free_flow_travel_time_s": free_flow_time,
            "delay_s": delay,
            "road_closure": bool(data.get("roadClosure", False)),
            "confidence": data.get("confidence"),
            "source": "tomtom",
        }
        _store(cache_key, result, 20)
        return result
    except Exception:
        # TomTom is an enhancement; keep the existing NDW/OSM flow available.
        _store(cache_key, None, 10)
        return None


def _first_coordinate(geometry):
    coords = (geometry or {}).get("coordinates") or []
    geometry_type = (geometry or {}).get("type")
    if geometry_type == "Point":
        return coords if len(coords) >= 2 else None
    if geometry_type == "LineString":
        return coords[0] if coords and len(coords[0]) >= 2 else None
    if geometry_type == "MultiLineString":
        return coords[0][0] if coords and coords[0] and len(coords[0][0]) >= 2 else None
    return None


def fetch_incidents(lat, lng, radius_km=15):
    """Fetch current TomTom incidents near the driver for the map/alerts."""
    api_key = os.environ.get("TOMTOM_API_KEY")
    if not api_key:
        return []

    cache_key = ("incidents", round(lat, 2), round(lng, 2), round(radius_km, 1))
    hit, cached = _cached(cache_key)
    if hit:
        return cached

    margin = radius_km / 111.0
    bbox = f"{lng - margin},{lat - margin},{lng + margin},{lat + margin}"
    fields = "{incidents{type,geometry{type,coordinates},properties{iconCategory,description,delay}}}"
    try:
        response = requests.post(
            TOMTOM_INCIDENTS_URL,
            params={
                "key": api_key,
                "bbox": bbox,
                "fields": fields,
                "language": "nl-NL",
                "timeValidityFilter": "present",
            },
            headers={"User-Agent": "FlitsMaatje/1.1"},
            timeout=8,
        )
        response.raise_for_status()
        reports = []
        for index, incident in enumerate(response.json().get("incidents", [])):
            coordinate = _first_coordinate(incident.get("geometry"))
            if not coordinate:
                continue
            props = incident.get("properties") or {}
            category = int(props.get("iconCategory") or 0)
            report_type = {
                1: "ongeval", 6: "file", 7: "wegwerkzaamheden",
                8: "wegwerkzaamheden", 9: "wegwerkzaamheden",
            }.get(category, "gevaar")
            reports.append({
                "id": f"tomtom-{index}-{coordinate[1]}-{coordinate[0]}",
                "type": report_type,
                "lat": float(coordinate[1]),
                "lng": float(coordinate[0]),
                "description": (props.get("description") or "TomTom verkeersmelding")[:240],
                "delay_s": props.get("delay"),
                "created_at": time.time(),
                "expires_at": time.time() + 15 * 60,
            })
        _store(cache_key, reports, 60)
        return reports
    except Exception:
        _store(cache_key, [], 15)
        return []
