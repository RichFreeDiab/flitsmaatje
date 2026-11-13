"""Route-corridor matching, alert ranking, and drive-context helpers."""

from __future__ import annotations

import math
import time

CORRIDOR_HALF_WIDTH_M = 45.0
CORRIDOR_WIDE_M = {
    "trajectcontrole": 80.0,
    "file": 90.0,
    "wegwerkzaamheden": 70.0,
}

EARLY_TYPES = frozenset({
    "flitser_mobiel",
    "politie",
    "ongeval",
    "gevaar",
})

FIXED_TYPES = frozenset({
    "flitser_vast",
    "trajectcontrole",
})

SOURCE_PRIORITY = {
    "anwb": 92,
    "ANWB": 92,
    "crowd": 70,
    "ndw": 76,
    "tomtom": 66,
    "scdb": 52,
    "osm": 45,
    "unknown": 40,
}

ALERT_KIND = {
    "flitser_vast": "fixed",
    "trajectcontrole": "average",
    "flitser_mobiel": "mobile",
    "politie": "mobile",
    "file": "jam",
    "ongeval": "incident",
    "gevaar": "incident",
    "wegwerkzaamheden": "incident",
}


def haversine_m(lat1, lng1, lat2, lng2):
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def parse_route_points(raw):
    """Parse compact route=lat,lng;lat,lng;... into [(lat, lng), ...]."""
    if not raw:
        return []
    points = []
    for part in str(raw).split(";"):
        part = part.strip()
        if not part:
            continue
        try:
            lat_s, lng_s = part.split(",", 1)
            lat = float(lat_s)
            lng = float(lng_s)
        except (TypeError, ValueError):
            continue
        if -90 <= lat <= 90 and -180 <= lng <= 180:
            if not points or abs(points[-1][0] - lat) > 1e-7 or abs(points[-1][1] - lng) > 1e-7:
                points.append((lat, lng))
    if len(points) > 200:
        step = max(1, len(points) // 200)
        points = points[::step]
        if points[-1] != points[-1]:
            pass
    return points


def _point_to_segment_m(px, py, ax, ay, bx, by):
    """Approximate meters using local equirectangular projection."""
    mean_lat = math.radians((ay + by + py) / 3.0)
    x_m = lambda lng, lat: (lng - ax) * 111320.0 * math.cos(mean_lat)
    y_m = lambda lat: (lat - ay) * 110540.0
    axm, aym = 0.0, 0.0
    bxm, bym = x_m(bx, by), y_m(by)
    pxm, pym = x_m(px, py), y_m(py)
    dx, dy = bxm - axm, bym - aym
    if dx == 0 and dy == 0:
        return math.hypot(pxm - axm, pym - aym)
    t = max(0.0, min(1.0, ((pxm - axm) * dx + (pym - aym) * dy) / (dx * dx + dy * dy)))
    return math.hypot(pxm - (axm + t * dx), pym - (aym + t * dy))


def distance_to_corridor_m(lat, lng, route_points):
    if not route_points:
        return None
    if len(route_points) == 1:
        return haversine_m(lat, lng, route_points[0][0], route_points[0][1])
    best = None
    for i in range(len(route_points) - 1):
        a = route_points[i]
        b = route_points[i + 1]
        dist = _point_to_segment_m(lng, lat, a[1], a[0], b[1], b[0])
        if best is None or dist < best:
            best = dist
    return best


def opposite_bearing(bearing):
    if bearing is None:
        return None
    try:
        return (float(bearing) + 180.0) % 360.0
    except (TypeError, ValueError):
        return None


def alert_kind_for(report_type):
    return ALERT_KIND.get(report_type, "incident")


def geometry_for(candidate):
    polyline = candidate.get("polyline")
    if polyline and len(polyline) >= 2:
        return "line"
    if candidate.get("geometry") == "line":
        return "line"
    return "point"


def infer_source(candidate):
    source = candidate.get("source")
    if source:
        return source
    cid = str(candidate.get("id") or "")
    if cid.startswith("anwb-"):
        return "anwb"
    if cid.startswith("tomtom-"):
        return "tomtom"
    if cid.startswith("ndw-") or cid.startswith("NDW"):
        return "ndw"
    if cid.startswith("osm-") or cid.startswith("scdb-"):
        return "osm" if cid.startswith("osm-") else "scdb"
    return "crowd"


def confidence_for(candidate, now=None):
    now = now or time.time()
    confirms = int(candidate.get("confirms") or 0)
    base = 0.45 + min(0.35, confirms * 0.05)
    source = infer_source(candidate)
    if source in ("anwb", "ANWB"):
        base = max(base, 0.85)
    elif source == "ndw":
        base = max(base, 0.75)
    elif source == "tomtom":
        base = max(base, 0.7)
    created = candidate.get("created_at")
    if created:
        try:
            age_h = max(0.0, (now - float(created)) / 3600.0)
            base *= max(0.55, 1.0 - age_h * 0.08)
        except (TypeError, ValueError):
            pass
    return round(min(0.99, base), 3)


def priority_for(candidate):
    source = infer_source(candidate)
    priority = SOURCE_PRIORITY.get(source, SOURCE_PRIORITY["unknown"])
    kind = alert_kind_for(candidate.get("type"))
    if kind == "mobile":
        priority += 8
    elif kind == "average":
        priority += 4
    elif kind == "fixed":
        priority -= 5
    confirms = int(candidate.get("confirms") or 0)
    priority += min(10, confirms)
    return int(priority)


def enrich_candidate(candidate, user_lat, user_lng, user_heading=None, route_points=None, now=None):
    """Return a copy with ranking metadata and distances."""
    now = now or time.time()
    item = dict(candidate)
    dist_m = haversine_m(user_lat, user_lng, item["lat"], item["lng"])
    corridor_m = distance_to_corridor_m(item["lat"], item["lng"], route_points) if route_points else None
    heading = item.get("heading")
    bearing2 = item.get("bearing2")
    if bearing2 is None:
        bearing2 = opposite_bearing(heading)
    item["distance_m"] = round(dist_m)
    item["corridor_m"] = None if corridor_m is None else round(corridor_m, 1)
    item["bearing"] = heading
    item["bearing2"] = bearing2
    item["priority"] = priority_for(item)
    item["confidence"] = confidence_for(item, now=now)
    item["road_ref"] = item.get("road_ref") or item.get("road")
    item["hectometer"] = item.get("hectometer") or item.get("hm")
    item["geometry"] = geometry_for(item)
    item["alert_kind"] = alert_kind_for(item.get("type"))
    item["source"] = infer_source(item)
    return item


def on_corridor(item, route_points):
    if not route_points:
        return True
    corridor_m = item.get("corridor_m")
    if corridor_m is None:
        corridor_m = distance_to_corridor_m(item["lat"], item["lng"], route_points)
    width = CORRIDOR_WIDE_M.get(item.get("type"), CORRIDOR_HALF_WIDTH_M)
    return corridor_m is not None and corridor_m <= width


def rank_score(item, user_heading=None, heading_matches_fn=None):
    """Higher is better — not nearest-only."""
    dist_m = float(item.get("distance_m") or 0)
    corridor_m = item.get("corridor_m")
    priority = float(item.get("priority") or 0)
    confidence = float(item.get("confidence") or 0.5)
    score = priority + confidence * 50.0
    score += max(0.0, 1200.0 - dist_m) / 12.0
    if corridor_m is not None:
        score += max(0.0, 100.0 - float(corridor_m))
    heading = item.get("heading") or item.get("bearing")
    heading2 = item.get("bearing2")
    if user_heading is not None and heading_matches_fn is not None:
        primary_ok = heading_matches_fn(user_heading, heading)
        secondary_ok = heading_matches_fn(user_heading, heading2, tolerance=50)
        if primary_ok:
            score += 35
        elif secondary_ok:
            score -= 40  # likely opposite carriageway
        elif heading is not None:
            score -= 25
    if item.get("alert_kind") == "mobile":
        score += 12
    if item.get("alert_kind") == "fixed" and (item.get("confidence") or 0) < 0.55:
        score -= 8
    return score


def is_early_warning(item, now=None):
    now = now or time.time()
    if item.get("type") in EARLY_TYPES:
        return True
    source = infer_source(item)
    if source in ("anwb", "ANWB"):
        return True
    if source == "ndw" and item.get("type") in ("ongeval", "gevaar", "file"):
        return True
    created = item.get("created_at")
    if source == "crowd" and created:
        try:
            if now - float(created) <= 45 * 60 and int(item.get("confirms") or 0) >= 2:
                return True
        except (TypeError, ValueError):
            pass
    return False


def serialize_alert(item, type_labels, type_icons):
    report_type = item["type"]
    payload = {
        "id": item["id"],
        "type": report_type,
        "label": type_labels.get(report_type, report_type),
        "icon": type_icons.get(report_type, "⚠️"),
        "distance_m": int(item.get("distance_m") or 0),
        "lat": item["lat"],
        "lng": item["lng"],
        "confirms": int(item.get("confirms") or 0),
        "bearing": item.get("bearing"),
        "bearing2": item.get("bearing2"),
        "priority": item.get("priority"),
        "confidence": item.get("confidence"),
        "road_ref": item.get("road_ref"),
        "hectometer": item.get("hectometer"),
        "geometry": item.get("geometry") or "point",
        "alert_kind": item.get("alert_kind") or alert_kind_for(report_type),
        "source": item.get("source"),
    }
    polyline = item.get("polyline")
    if polyline:
        payload["polyline"] = polyline
    if item.get("corridor_m") is not None:
        payload["corridor_m"] = item.get("corridor_m")
    return payload


def select_ranked_alert(candidates, warn_distance_m, user_heading=None, route_points=None, heading_matches_fn=None):
    """Pick best alert using ranking; apply warn distance + optional corridor."""
    ranked = []
    for raw in candidates:
        item = raw if "distance_m" in raw and "priority" in raw else raw
        dist_m = float(item.get("distance_m") or 0)
        threshold = warn_distance_m.get(item.get("type"), 800)
        if dist_m > threshold:
            continue
        if route_points:
            if not on_corridor(item, route_points):
                continue
        elif (
            user_heading is not None
            and item.get("heading") is not None
            and heading_matches_fn is not None
            and not heading_matches_fn(user_heading, item.get("heading"))
        ):
            # Dashboard-modus: behoud legacy heading-filter tegen tegenliggers.
            continue
        score = rank_score(item, user_heading=user_heading, heading_matches_fn=heading_matches_fn)
        ranked.append((score, item))
    if not ranked:
        return None
    ranked.sort(key=lambda pair: pair[0], reverse=True)
    return ranked[0][1]


def partition_drive_context(enriched, warn_distance_m, user_heading=None, route_points=None, heading_matches_fn=None):
    usable = []
    for item in enriched:
        if route_points and not on_corridor(item, route_points):
            continue
        usable.append(item)

    speed_traps = []
    speed_traps_alt = []
    incidents = []
    traffic_jams = []
    early = []

    for item in usable:
        kind = item.get("alert_kind") or alert_kind_for(item.get("type"))
        if kind in ("fixed", "average", "mobile"):
            if kind == "fixed":
                speed_traps.append(item)
            else:
                speed_traps_alt.append(item)
        elif kind == "jam":
            traffic_jams.append(item)
        else:
            incidents.append(item)
        if is_early_warning(item):
            early.append(item)

    def by_score(items):
        return sorted(
            items,
            key=lambda it: rank_score(it, user_heading=user_heading, heading_matches_fn=heading_matches_fn),
            reverse=True,
        )

    speed_traps = by_score(speed_traps)
    speed_traps_alt = by_score(speed_traps_alt)
    incidents = by_score(incidents)
    traffic_jams = by_score(traffic_jams)
    early = by_score(early)

    top = select_ranked_alert(
        usable,
        warn_distance_m,
        user_heading=user_heading,
        route_points=route_points,
        heading_matches_fn=heading_matches_fn,
    )
    return {
        "speed_traps": speed_traps,
        "speed_traps_alt": speed_traps_alt,
        "incidents": incidents,
        "traffic_jams": traffic_jams,
        "early": early,
        "alert": top,
        "all": usable,
    }


def normalize_lane_sections(sections):
    """Attach FM-style items [{directionType, isActive}] to each section."""
    normalized = []
    for section in sections or []:
        item = dict(section)
        lanes = item.get("lanes") or []
        guidance_items = []
        for lane in lanes:
            directions = lane.get("directions") or []
            follow = lane.get("follow")
            if not directions:
                guidance_items.append({"directionType": "straight", "isActive": False})
                continue
            # Prefer the follow arrow when present; otherwise first direction.
            primary = follow if follow in directions else directions[0]
            direction_type = str(primary).strip().lower().replace(" ", "_")
            is_active = follow is not None and (
                follow in directions or str(follow).upper() in [str(d).upper() for d in directions]
            )
            guidance_items.append({
                "directionType": direction_type,
                "isActive": bool(is_active),
            })
            # Keep raw lane payload but also expose normalized fields on lane.
            lane = dict(lane)
            lane["directionType"] = direction_type
            lane["isActive"] = bool(is_active)
        item["items"] = guidance_items
        # Rebuild lanes with normalized flags for clients that read lane.isActive.
        new_lanes = []
        for lane, guide in zip(lanes, guidance_items):
            entry = dict(lane)
            entry["directionType"] = guide["directionType"]
            entry["isActive"] = guide["isActive"]
            new_lanes.append(entry)
        item["lanes"] = new_lanes
        normalized.append(item)
    return normalized


def extract_polyline(geometry):
    """Return [[lat, lng], ...] from GeoJSON-like TomTom geometry."""
    if not geometry:
        return None
    coords = geometry.get("coordinates") or []
    gtype = geometry.get("type")
    points = []
    if gtype == "LineString":
        for pair in coords:
            if isinstance(pair, (list, tuple)) and len(pair) >= 2:
                points.append([float(pair[1]), float(pair[0])])
    elif gtype == "MultiLineString":
        for line in coords:
            for pair in line or []:
                if isinstance(pair, (list, tuple)) and len(pair) >= 2:
                    points.append([float(pair[1]), float(pair[0])])
    if len(points) >= 2:
        if len(points) > 80:
            step = max(1, len(points) // 80)
            points = points[::step]
        return points
    return None
