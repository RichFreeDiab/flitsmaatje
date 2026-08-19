"""Server-side TomTom Traffic integration.

The API key is deliberately read only from TOMTOM_API_KEY. Never ship it in
the iOS app or commit it to the repository.
"""
import math
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


def fetch_lane_guidance(origin_lat, origin_lng, destination_lat, destination_lng, waypoints=None):
    """Fetch TomTom v1 lane sections for the active route."""
    api_key = os.environ.get("TOMTOM_API_KEY")
    if not api_key:
        return []
    route_points = [f"{origin_lat},{origin_lng}"]
    for waypoint in waypoints or []:
        lat = waypoint.get("lat")
        lng = waypoint.get("lng")
        if lat is None or lng is None:
            continue
        route_points.append(f"{lat},{lng}")
    route_points.append(f"{destination_lat},{destination_lng}")
    route_path = ":".join(route_points)
    cache_key = ("lanes", route_path)
    hit, cached = _cached(cache_key)
    if hit:
        return cached
    try:
        response = requests.get(
            f"{TOMTOM_ROUTING_URL}/{route_path}/json",
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
            _store(cache_key, [], ttl=45)
            return []
        route = routes[0]
        sections = route.get("sections") or []
        geometry_points = []
        for leg in route.get("legs") or []:
            for point in leg.get("points") or []:
                if not geometry_points or point != geometry_points[-1]:
                    geometry_points.append(point)
        result = []
        for section in sections:
            if str(section.get("sectionType", "")).upper() != "LANES":
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
                start_point = geometry_points[start_index] if 0 <= start_index < len(geometry_points) else {}
                end_point = geometry_points[end_index] if 0 <= end_index < len(geometry_points) else {}
                result.append({
                    "start_point_index": start_index,
                    "end_point_index": end_index,
                    "start_lat": start_point.get("latitude"),
                    "start_lng": start_point.get("longitude"),
                    "end_lat": end_point.get("latitude"),
                    "end_lng": end_point.get("longitude"),
                    "lanes": lanes,
                })
        _store(cache_key, result, ttl=45)
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
        # Snap to Roads vereist minimaal twee GPS-punten. Een tweede punt op
        # circa één meter noordwaarts is voldoende om de huidige weg te
        # matchen zonder een verzonnen langere route te construeren.
        points = f"{lng},{lat};{lng},{lat + 0.00001}"
        response = requests.get(
            TOMTOM_SNAP_URL,
            params={
                "key": api_key,
                "points": points,
                "fields": fields,
                "vehicleType": "PassengerCar",
                "measurementSystem": "metric",
                "offroadMargin": 50,
            },
            headers={"User-Agent": "FlitsMaatje/1.1"},
            timeout=5,
        )
        response.raise_for_status()
        route = response.json().get("route") or []
        if isinstance(route, dict):
            route = [route]
        for segment in route:
            properties = segment.get("properties") or {}
            limits = properties.get("speedLimits") or []
            if isinstance(limits, dict):
                limits = [limits]
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


def fetch_tomtom_reverse_speed_limit(lat, lng):
    """Speed limit + road via Reverse Geocode (werkt vaak als Snap/Flow credits op zijn)."""
    api_key = os.environ.get("TOMTOM_API_KEY")
    if not api_key:
        return None
    cache_key = ("rev_limit", round(lat, 4), round(lng, 4))
    hit, cached = _cached(cache_key)
    if hit:
        return cached
    try:
        response = requests.get(
            f"https://api.tomtom.com/search/2/reverseGeocode/{lat},{lng}.json",
            params={
                "key": api_key,
                "returnSpeedLimit": "true",
                "radius": 80,
            },
            headers={"User-Agent": "FlitsMaatje/1.1"},
            timeout=4,
        )
        response.raise_for_status()
        addresses = response.json().get("addresses") or []
        if not addresses:
            _store(cache_key, None, 30)
            return None
        address = addresses[0].get("address") or {}
        raw_limit = address.get("speedLimit")
        maxspeed = None
        if raw_limit:
            text = str(raw_limit).upper().replace(",", ".")
            digits = "".join(ch if (ch.isdigit() or ch == ".") else " " for ch in text).split()
            if digits:
                value = float(digits[0])
                if "MPH" in text:
                    value *= 1.60934
                maxspeed = int(round(value))
        route_numbers = address.get("routeNumbers") or []
        road_name = None
        if route_numbers:
            road_name = str(route_numbers[0])
        else:
            road_name = address.get("streetName") or address.get("street") or address.get("freeformAddress")
        if maxspeed is None and not road_name:
            _store(cache_key, None, 30)
            return None
        result = {
            "maxspeed": maxspeed,
            "road_name": road_name,
            "source": "tomtom_reverse_geocode",
        }
        _store(cache_key, result, 300)
        return result
    except (requests.RequestException, ValueError, TypeError, KeyError):
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


def _line_heading(geometry):
    coords = (geometry or {}).get("coordinates") or []
    geometry_type = (geometry or {}).get("type")
    a = b = None
    if geometry_type == "LineString" and len(coords) >= 2:
        a, b = coords[0], coords[-1]
    elif geometry_type == "MultiLineString" and coords and len(coords[0]) >= 2:
        a, b = coords[0][0], coords[0][-1]
    if not a or not b or len(a) < 2 or len(b) < 2:
        return None
    try:
        lat1 = math.radians(float(a[1]))
        lat2 = math.radians(float(b[1]))
        delta_lng = math.radians(float(b[0]) - float(a[0]))
    except (TypeError, ValueError, IndexError):
        return None
    y = math.sin(delta_lng) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(delta_lng)
    return round((math.degrees(math.atan2(y, x)) + 360) % 360, 1)


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


def _request_incidents(api_key, bbox, fields):
    params = {
        "key": api_key,
        "bbox": bbox,
        "fields": fields,
        "language": "nl-NL",
        "timeValidityFilter": "present",
    }
    headers = {"User-Agent": "FlitsMaatje/1.1"}
    last_error = None
    for method in ("post", "get"):
        try:
            response = getattr(requests, method)(
                TOMTOM_INCIDENTS_URL,
                params=params,
                headers=headers,
                timeout=8,
            )
            response.raise_for_status()
            return response.json()
        except Exception as error:
            last_error = error
    raise last_error or RuntimeError("TomTom incidents onbereikbaar")


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
    fields = (
        "{incidents{type,geometry{type,coordinates},"
        "properties{id,iconCategory,description,delay,from,to}}}"
    )
    try:
        payload = _request_incidents(api_key, bbox, fields)
        reports = []
        for index, incident in enumerate(payload.get("incidents") or []):
            geometry = incident.get("geometry")
            coordinate = _first_coordinate(geometry)
            if not coordinate:
                continue
            props = incident.get("properties") or {}
            category = int(props.get("iconCategory") or 0)
            report_type = {
                1: "ongeval",
                6: "file",
                7: "wegwerkzaamheden",
                8: "wegwerkzaamheden",
                9: "wegwerkzaamheden",
            }.get(category, "gevaar")
            incident_id = props.get("id") or f"{index}-{coordinate[1]}-{coordinate[0]}"
            reports.append({
                "id": f"tomtom-{incident_id}",
                "type": report_type,
                "lat": float(coordinate[1]),
                "lng": float(coordinate[0]),
                "heading": _line_heading(geometry),
                "description": (props.get("description") or "TomTom verkeersmelding")[:240],
                "delay_s": props.get("delay"),
                "road": props.get("from") or props.get("to"),
                "created_at": time.time(),
                "expires_at": time.time() + 15 * 60,
            })
        _store(cache_key, reports, 60)
        return reports
    except Exception:
        _store(cache_key, [], 15)
        return []
