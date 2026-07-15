"""
FlitsMaatje - Crowdsourced verkeersmeldingen app (Flitsmeister-achtig)
Flask backend met SQLite. Bedoeld als MVP, draait standalone op poort 5068.

Functies:
- GET  /api/reports          -> actieve meldingen binnen straal van lat/lng
- GET  /api/nearby-alert     -> dichtstbijzijnde waarschuwing (iOS-widget/CarPlay)
- POST /api/reports          -> nieuwe melding aanmaken
- POST /api/reports/<id>/vote -> bevestigen ("nog aanwezig") of ontkennen ("weg")
- Achtergrondtaak ruimt verlopen meldingen op (lazy, bij elke GET)
"""

import os
import sqlite3
import time
import math
import uuid
from pathlib import Path
import requests
from flask import Flask, request, jsonify, g, send_from_directory

DB_PATH = Path(__file__).parent / "flitsmaatje.db"

app = Flask(__name__, static_folder="static", template_folder="templates")

# Hoe lang een melding "geldig" blijft (seconden), per type.
# Vaste flitsers/trajectcontroles blijven praktisch permanent staan,
# de rest verdwijnt vanzelf na een tijd (zoals in Flitsmeister/Waze).
EXPIRY_SECONDS = {
    "flitser_vast": 60 * 60 * 24 * 365,      # vaste flitser: 1 jaar (i.e. permanent-ish)
    "trajectcontrole": 60 * 60 * 24 * 365,   # trajectcontrole: idem
    "flitser_mobiel": 60 * 60 * 2,           # mobiele flitser/flitswagen: 2 uur
    "politie": 60 * 60 * 1,                  # politiecontrole: 1 uur
    "ongeval": 60 * 60 * 3,                  # ongeval: 3 uur
    "file": 60 * 60 * 2,                     # file: 2 uur
    "gevaar": 60 * 60 * 4,                   # gevaar op de weg (obstakel, olie, etc): 4 uur
    "wegwerkzaamheden": 60 * 60 * 24 * 7,    # wegwerkzaamheden: 1 week
}
DEFAULT_EXPIRY = 60 * 60 * 2

# Waarschuwingsafstand (meters) per type — zelfde waarden als static/js/app.js
WARN_DISTANCE_M = {
    "flitser_vast": 800,
    "flitser_mobiel": 800,
    "trajectcontrole": 1500,
    "politie": 800,
    "ongeval": 600,
    "file": 1000,
    "gevaar": 500,
    "wegwerkzaamheden": 500,
}

TYPE_LABELS = {
    "flitser_vast": "Vaste flitser",
    "flitser_mobiel": "Mobiele flitser",
    "trajectcontrole": "Trajectcontrole",
    "politie": "Politiecontrole",
    "ongeval": "Ongeval",
    "file": "File",
    "gevaar": "Gevaar op de weg",
    "wegwerkzaamheden": "Wegwerkzaamheden",
}

TYPE_ICONS = {
    "flitser_vast": "📷",
    "flitser_mobiel": "🚐",
    "trajectcontrole": "📡",
    "politie": "👮",
    "ongeval": "💥",
    "file": "🚗",
    "gevaar": "⚠️",
    "wegwerkzaamheden": "🚧",
}

# Onder dit aantal "weg"-stemmen (netto) wordt een melding direct verwijderd
DENY_THRESHOLD = -3


def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH, timeout=15)
        g.db.execute("PRAGMA busy_timeout = 15000")
        g.db.execute("PRAGMA journal_mode = WAL")
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(exception=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS reports (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            heading REAL,
            created_at REAL NOT NULL,
            expires_at REAL NOT NULL,
            confirms INTEGER NOT NULL DEFAULT 1,
            denies INTEGER NOT NULL DEFAULT 0
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_lat_lng ON reports(lat, lng)")
    conn.commit()
    conn.close()


def haversine_km(lat1, lng1, lat2, lng2):
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


# ---------------------------------------------------------------------------
# Overpass / OpenStreetMap snelheidslimiet-lookup
# ---------------------------------------------------------------------------
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
OVERPASS_TIMEOUT = 8  # seconden
OVERPASS_HEADERS = {"User-Agent": "FlitsMaatje/1.0 (https://flitsmaatje.readvanes.nl)", "Accept": "application/json"}

# Cache: key = (lat afgerond op 4 decimalen, lng afgerond op 4 decimalen) -> (resultaat, timestamp)
# 4 decimalen lat/lng is ~11 meter precisie, ruim genoeg voor wegsegmenten en scheelt
# enorm veel calls naar de (gratis, rate-limited) Overpass API.
_speed_limit_cache = {}
SPEED_LIMIT_CACHE_TTL = 120  # seconden

# Als een weg geen expliciete maxspeed-tag heeft, vallen we terug op een
# vuistregel per wegtype (Nederlandse standaardlimieten). Dit is een
# benadering: de officiële, geldende limiet wordt altijd bepaald door de
# bebording ter plaatse, niet door deze app.
DEFAULT_LIMIT_BY_HIGHWAY = {
    "motorway": 100,
    "motorway_link": 100,
    "trunk": 100,
    "trunk_link": 80,
    "primary": 80,
    "primary_link": 80,
    "secondary": 80,
    "secondary_link": 80,
    "tertiary": 80,
    "tertiary_link": 80,
    "residential": 50,
    "living_street": 15,
    "service": 30,
    "unclassified": 60,
}


def classify_zone(highway_type, maxspeed):
    """Leid de boete-zone af (bebouwde kom / buiten bebouwde kom / snelweg)."""
    if highway_type in ("motorway", "motorway_link", "trunk", "trunk_link"):
        return "snelweg"
    if maxspeed is not None:
        if maxspeed >= 90:
            return "snelweg"
        if maxspeed <= 50:
            return "bebouwde_kom"
        return "buiten_bebouwde_kom"
    if highway_type in ("residential", "living_street", "service"):
        return "bebouwde_kom"
    return "buiten_bebouwde_kom"


def fetch_speed_limit(lat, lng):
    """Vraag de dichtstbijzijnde weg met snelheidslimiet op via Overpass."""
    cache_key = (round(lat, 4), round(lng, 4))
    cached = _speed_limit_cache.get(cache_key)
    if cached and (time.time() - cached[1]) < SPEED_LIMIT_CACHE_TTL:
        return cached[0]

    query = f"""
        [out:json][timeout:{OVERPASS_TIMEOUT}];
        way(around:35,{lat},{lng})[highway];
        out tags;
    """

    try:
        resp = requests.post(OVERPASS_URL, data={"data": query}, headers=OVERPASS_HEADERS, timeout=OVERPASS_TIMEOUT)
        resp.raise_for_status()
        data = resp.json()
    except Exception as e:
        # Overpass niet bereikbaar of timeout: geen limiet teruggeven i.p.v. de app te laten crashen
        return {"maxspeed": None, "zone": None, "road_name": None, "source": "unavailable", "error": str(e)}

    elements = data.get("elements", [])
    if not elements:
        result = {"maxspeed": None, "zone": None, "road_name": None, "source": "not_found"}
        _speed_limit_cache[cache_key] = (result, time.time())
        return result

    # Kies de eerste weg met een expliciete maxspeed-tag; anders de eerste weg met een highway-type
    chosen = None
    for el in elements:
        tags = el.get("tags", {})
        if "maxspeed" in tags:
            chosen = el
            break
    if chosen is None:
        chosen = elements[0]

    tags = chosen.get("tags", {})
    highway_type = tags.get("highway")
    road_name = tags.get("name")

    maxspeed_raw = tags.get("maxspeed")
    maxspeed = None
    source = "osm_tag"
    if maxspeed_raw:
        digits = "".join(ch for ch in maxspeed_raw if ch.isdigit())
        if digits:
            maxspeed = int(digits)

    if maxspeed is None:
        maxspeed = DEFAULT_LIMIT_BY_HIGHWAY.get(highway_type)
        source = "default_estimate"

    zone = classify_zone(highway_type, maxspeed)

    result = {
        "maxspeed": maxspeed,
        "zone": zone,
        "road_name": road_name,
        "highway_type": highway_type,
        "source": source,
    }
    _speed_limit_cache[cache_key] = (result, time.time())
    return result


# ---------------------------------------------------------------------------
# Boetecalculator (CJIB / OM Boetebase tarieven 2026)
# Bedragen zijn EXCLUSIEF de vaste 9 euro administratiekosten van het CJIB.
# Dit is een indicatieve schatting voor eigen gebruik, geen juridisch advies
# en geen vervanging voor de officiële OM Boetebase (www2.om.nl/boetebase).
# ---------------------------------------------------------------------------
FINE_TABLE = {
    "bebouwde_kom": {4: 37, 5: 44, 6: 52, 7: 61, 8: 70, 9: 81, 10: 95, 15: 175, 20: 255, 25: 345, 30: 455},
    "buiten_bebouwde_kom": {4: 33, 5: 40, 6: 47, 7: 55, 8: 64, 9: 73, 10: 81, 15: 165, 20: 235, 25: 325, 30: 430},
    "snelweg": {4: 28, 5: 34, 6: 40, 7: 47, 8: 55, 9: 63, 10: 77, 15: 140, 20: 210, 25: 295, 30: 395, 35: 520},
}
ADMIN_COST = 9
OM_THRESHOLD = {"bebouwde_kom": 35, "buiten_bebouwde_kom": 35, "snelweg": 36}


def estimate_fine(zone, measured_kmh, limit_kmh):
    """Schat de boete op basis van gemeten snelheid en geldende limiet.

    Past de gangbare meetcorrectie toe (3 km/u tot 100 km/u, daarboven 3%),
    zoals de politie die ook hanteert, voordat de overschrijding wordt bepaald.
    """
    if zone not in FINE_TABLE or limit_kmh is None:
        return None

    if measured_kmh <= 100:
        corrected = measured_kmh - 3
    else:
        corrected = measured_kmh * 0.97

    excess = math.floor(corrected - limit_kmh)
    if excess < 4:
        return {"excess_kmh": max(excess, 0), "bedrag": 0, "om_zaak": False, "indicatief": True}

    if excess >= OM_THRESHOLD.get(zone, 35):
        return {"excess_kmh": excess, "bedrag": None, "om_zaak": True, "indicatief": True}

    table = FINE_TABLE[zone]
    keys = sorted(table.keys())

    if excess in table:
        bedrag = table[excess]
    else:
        # Lineair interpoleren tussen de twee dichtstbijzijnde bekende staffelpunten
        lower = max([k for k in keys if k < excess], default=keys[0])
        upper = min([k for k in keys if k > excess], default=keys[-1])
        if lower == upper:
            bedrag = table[lower]
        else:
            frac = (excess - lower) / (upper - lower)
            bedrag = round(table[lower] + frac * (table[upper] - table[lower]))

    return {
        "excess_kmh": excess,
        "bedrag": bedrag + ADMIN_COST,
        "bedrag_excl_administratiekosten": bedrag,
        "om_zaak": False,
        "indicatief": True,
    }


def cleanup_expired(db):
    db.execute("DELETE FROM reports WHERE expires_at < ?", (time.time(),))
    db.commit()


@app.route("/")
def index():
    return send_from_directory(app.template_folder, "index.html")


@app.route("/carplay")
def carplay_simulator():
    """Webpreview van het CarPlay Dashboard-widget (zelfde /api/nearby-alert als iOS)."""
    return send_from_directory(app.template_folder, "carplay.html")


@app.route("/carplay-submit")
def carplay_submit_screenshot():
    """Statische CarPlay-navigatie-screenshots voor Apple-aanvraag (?scene=nav|search|alert)."""
    from flask import render_template
    scene = request.args.get("scene", "nav")
    if scene not in {"nav", "search", "alert"}:
        scene = "nav"
    return render_template("carplay-submit.html", scene=scene)


@app.after_request
def carplay_submit_cors(response):
    if request.path.startswith("/static/carplay-submit/"):
        response.headers["Access-Control-Allow-Origin"] = "*"
    return response


@app.route("/sw.js")
def service_worker():
    return send_from_directory(app.static_folder, "sw.js", mimetype="application/javascript")


DIAGNOSTIC_LOG_DIR = Path(__file__).parent / "diagnostic_logs"


@app.route("/api/diagnostic-log", methods=["POST"])
def diagnostic_log():
    """Ontvang iOS-diagnostieklogs van TestFlight-builds (crash-onderzoek)."""
    DIAGNOSTIC_LOG_DIR.mkdir(exist_ok=True)
    body = request.get_data(as_text=True) or ""
    reason = (request.headers.get("X-Log-Reason") or "unknown")[:40]
    device = (request.headers.get("X-Device-Id") or "device")[:60]
    version = (request.headers.get("X-App-Version") or "unknown")[:20]
    safe_device = "".join(c if c.isalnum() or c in "-_" else "_" for c in device)
    filename = f"{time.strftime('%Y%m%d-%H%M%S')}-{reason}-{version}-{safe_device}.log"
    (DIAGNOSTIC_LOG_DIR / filename).write_text(body, encoding="utf-8")
    return jsonify({"ok": True, "file": filename})


@app.route("/api/diagnostic-logs", methods=["GET"])
def diagnostic_logs_list():
    """Overzicht van ontvangen diagnostieklogs (intern/debug)."""
    DIAGNOSTIC_LOG_DIR.mkdir(exist_ok=True)
    files = sorted(DIAGNOSTIC_LOG_DIR.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    return jsonify([
        {"file": f.name, "bytes": f.stat().st_size, "mtime": f.stat().st_mtime}
        for f in files[:30]
    ])


@app.route("/api/carplay-selftest", methods=["GET"])
def carplay_selftest():
    """Simuleer iOS-opstart + CarPlay-gedrag — draait vóór TestFlight-deploy."""
    import importlib.util
    import sys

    script = Path(__file__).parent / "scripts" / "carplay_selftest.py"
    spec = importlib.util.spec_from_file_location("carplay_selftest", script)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules["carplay_selftest"] = module
    spec.loader.exec_module(module)

    base = request.url_root.rstrip("/")
    seed = request.args.get("seed", "1") != "0"
    result = module.run_selftest(base_url=base, seed_demo=seed)
    return jsonify(result.as_dict()), (200 if result.ok else 500)


@app.route("/api/speed-check", methods=["GET"])
def speed_check():
    """Geeft de geldende snelheidslimiet op deze locatie + boete-indicatie
    voor de meegegeven huidige snelheid (optioneel)."""
    try:
        lat = float(request.args.get("lat"))
        lng = float(request.args.get("lng"))
    except (TypeError, ValueError):
        return jsonify({"error": "lat en lng zijn verplicht"}), 400

    limit_info = fetch_speed_limit(lat, lng)

    speed_param = request.args.get("speed_kmh")
    fine = None
    if speed_param is not None and limit_info.get("maxspeed") is not None and limit_info.get("zone") is not None:
        try:
            speed_kmh = float(speed_param)
            fine = estimate_fine(limit_info["zone"], speed_kmh, limit_info["maxspeed"])
        except ValueError:
            pass

    return jsonify({"limit": limit_info, "fine": fine})


@app.route("/api/reports", methods=["GET"])
def get_reports():
    """Geef actieve meldingen terug binnen straal (km) van lat/lng."""
    try:
        lat = float(request.args.get("lat"))
        lng = float(request.args.get("lng"))
    except (TypeError, ValueError):
        return jsonify({"error": "lat en lng zijn verplicht"}), 400

    radius_km = float(request.args.get("radius_km", 15))

    db = get_db()
    cleanup_expired(db)

    # Grove bounding box filter in SQL (sneller dan alles ophalen), daarna exacte haversine check
    deg_margin = radius_km / 111.0  # ~111km per breedtegraad
    rows = db.execute(
        """SELECT * FROM reports
           WHERE lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?""",
        (lat - deg_margin, lat + deg_margin, lng - deg_margin, lng + deg_margin),
    ).fetchall()

    results = []
    for row in rows:
        dist = haversine_km(lat, lng, row["lat"], row["lng"])
        if dist <= radius_km:
            results.append({
                "id": row["id"],
                "type": row["type"],
                "lat": row["lat"],
                "lng": row["lng"],
                "heading": row["heading"],
                "created_at": row["created_at"],
                "expires_at": row["expires_at"],
                "confirms": row["confirms"],
                "denies": row["denies"],
                "distance_km": round(dist, 3),
            })

    results.sort(key=lambda r: r["distance_km"])
    return jsonify({"reports": results})


@app.route("/api/nearby-alert", methods=["GET"])
def nearby_alert():
    """Lichtgewicht endpoint voor iOS-widget/app: dichtstbijzijnde actieve waarschuwing."""
    try:
        lat = float(request.args.get("lat"))
        lng = float(request.args.get("lng"))
    except (TypeError, ValueError):
        return jsonify({"error": "lat en lng zijn verplicht"}), 400

    radius_km = float(request.args.get("radius_km", 15))
    db = get_db()
    cleanup_expired(db)

    deg_margin = radius_km / 111.0
    rows = db.execute(
        """SELECT * FROM reports
           WHERE lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?""",
        (lat - deg_margin, lat + deg_margin, lng - deg_margin, lng + deg_margin),
    ).fetchall()

    closest = None
    closest_dist_m = None

    for row in rows:
        dist_km = haversine_km(lat, lng, row["lat"], row["lng"])
        if dist_km > radius_km:
            continue
        dist_m = dist_km * 1000
        threshold = WARN_DISTANCE_M.get(row["type"], 800)
        if dist_m <= threshold:
            if closest is None or dist_m < closest_dist_m:
                closest = row
                closest_dist_m = dist_m

    if closest is None:
        return jsonify({"alert": None})

    report_type = closest["type"]
    return jsonify({
        "alert": {
            "id": closest["id"],
            "type": report_type,
            "label": TYPE_LABELS.get(report_type, report_type),
            "icon": TYPE_ICONS.get(report_type, "⚠️"),
            "distance_m": round(closest_dist_m),
            "lat": closest["lat"],
            "lng": closest["lng"],
            "confirms": closest["confirms"],
        }
    })


@app.route("/api/reports", methods=["POST"])
def create_report():
    data = request.get_json(silent=True) or {}
    report_type = data.get("type")
    lat = data.get("lat")
    lng = data.get("lng")
    heading = data.get("heading")

    if report_type not in EXPIRY_SECONDS:
        return jsonify({"error": f"Onbekend type: {report_type}"}), 400
    if lat is None or lng is None:
        return jsonify({"error": "lat en lng zijn verplicht"}), 400

    db = get_db()
    cleanup_expired(db)

    # Dedupe: als er al een vergelijkbare melding binnen 150m en zelfde type bestaat,
    # tel die als bevestiging i.p.v. een dubbele melding aan te maken.
    deg_margin = 0.0015  # ~150m
    nearby = db.execute(
        """SELECT * FROM reports WHERE type = ?
           AND lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?""",
        (report_type, lat - deg_margin, lat + deg_margin, lng - deg_margin, lng + deg_margin),
    ).fetchall()

    for row in nearby:
        if haversine_km(lat, lng, row["lat"], row["lng"]) <= 0.15:
            new_expiry = time.time() + EXPIRY_SECONDS.get(report_type, DEFAULT_EXPIRY)
            db.execute(
                "UPDATE reports SET confirms = confirms + 1, expires_at = ? WHERE id = ?",
                (new_expiry, row["id"]),
            )
            db.commit()
            return jsonify({"status": "confirmed_existing", "id": row["id"]}), 200

    report_id = str(uuid.uuid4())
    now = time.time()
    expires_at = now + EXPIRY_SECONDS.get(report_type, DEFAULT_EXPIRY)

    db.execute(
        """INSERT INTO reports (id, type, lat, lng, heading, created_at, expires_at, confirms, denies)
           VALUES (?, ?, ?, ?, ?, ?, ?, 1, 0)""",
        (report_id, report_type, lat, lng, heading, now, expires_at),
    )
    db.commit()
    return jsonify({"status": "created", "id": report_id}), 201


@app.route("/api/reports/<report_id>/vote", methods=["POST"])
def vote_report(report_id):
    data = request.get_json(silent=True) or {}
    vote = data.get("vote")  # "confirm" of "deny"

    if vote not in ("confirm", "deny"):
        return jsonify({"error": "vote moet 'confirm' of 'deny' zijn"}), 400

    db = get_db()
    row = db.execute("SELECT * FROM reports WHERE id = ?", (report_id,)).fetchone()
    if row is None:
        return jsonify({"error": "melding niet gevonden"}), 404

    if vote == "confirm":
        db.execute(
            "UPDATE reports SET confirms = confirms + 1, expires_at = ? WHERE id = ?",
            (time.time() + EXPIRY_SECONDS.get(row["type"], DEFAULT_EXPIRY), report_id),
        )
    else:
        db.execute("UPDATE reports SET denies = denies + 1 WHERE id = ?", (report_id,))

    db.commit()

    updated = db.execute("SELECT * FROM reports WHERE id = ?", (report_id,)).fetchone()
    net_score = updated["confirms"] - updated["denies"]
    if net_score <= DENY_THRESHOLD:
        db.execute("DELETE FROM reports WHERE id = ?", (report_id,))
        db.commit()
        return jsonify({"status": "removed"}), 200

    return jsonify({"status": "ok", "confirms": updated["confirms"], "denies": updated["denies"]}), 200


init_db()

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "5068"))
    debug = os.environ.get("FLITSMAATJE_DEBUG", "0").lower() in {"1", "true", "yes"}
    app.run(host="0.0.0.0", port=port, debug=debug, use_reloader=debug)
