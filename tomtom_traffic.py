"""Server-side TomTom Traffic integration.

The API key is deliberately read only from TOMTOM_API_KEY. Never ship it in
the iOS app or commit it to the repository.
"""
import os
import time

import requests

TOMTOM_URL = "https://api.tomtom.com/traffic/services/4/flowSegmentData/absolute/10/json"
TOMTOM_INCIDENTS_URL = "https://api.tomtom.com/traffic/services/5/incidentDetails"


def fetch_flow_segment(lat, lng):
    api_key = os.environ.get("TOMTOM_API_KEY")
    if not api_key:
        return None

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
        return {
            "current_speed_kmh": current,
            "free_flow_speed_kmh": free_flow,
            "current_travel_time_s": travel_time,
            "free_flow_travel_time_s": free_flow_time,
            "delay_s": delay,
            "road_closure": bool(data.get("roadClosure", False)),
            "confidence": data.get("confidence"),
            "source": "tomtom",
        }
    except Exception:
        # TomTom is an enhancement; keep the existing NDW/OSM flow available.
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
        return reports
    except Exception:
        return []
