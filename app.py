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
import logging
from pathlib import Path
import requests
from flask import Flask, request, jsonify, g, send_from_directory
from ndw_feeds import sync_ndw_reports
from tomtom_traffic import fetch_flow_segment, fetch_incidents, fetch_tomtom_speed_limit, fetch_lane_guidance

# === LOGGING SETUP ===
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),  # stderr voor VPS/Docker
    ]
)
logger = logging.getLogger(__name__)

DB_PATH = Path(__file__).parent / "flitsmaatje.db"

app = Flask(__name__, static_folder="static", template_folder="templates")

# === DENY_THRESHOLD FIX ===
# Meldingen met meer "denies" dan "confirms" worden verwijderd
DENY_THRESHOLD = -3  # Dus: denies - confirms > 3 → verwijderd

# Hoe lang een melding "geldig" blijft (seconden), per type.
EXPIRY_SECONDS = {
    "flitser_vast": 60 * 60 * 24 * 365,      # vaste flitser: 1 jaar
    "trajectcontrole": 60 * 60 * 24 * 365,   # trajectcontrole: 1 jaar
    "flitser_mobiel": 60 * 60 * 2,           # mobiele flitser: 2 uur
    "politie": 60 * 60 * 1,                  # politiecontrole: 1 uur
    "ongeval": 60 * 60 * 3,                  # ongeval: 3 uur
    "file": 60 * 60 * 2,                     # file: 2 uur
    "gevaar": 60 * 60 * 4,                   # gevaar op de weg: 4 uur
    "wegwerkzaamheden": 60 * 60 * 24 * 7,    # wegwerkzaamheden: 1 week
}
DEFAULT_EXPIRY = 60 * 60 * 2

# Waarschuwingsafstand (meters) per type
ALERT_RADIUS_M = {
    "flitser_vast": 500,
    "flitser_mobiel": 300,
    "trajectcontrole": 1000,
    "politie": 300,
    "ongeval": 1000,
    "file": 500,
    "gevaar": 300,
    "wegwerkzaamheden": 200,
}

# Labels en iconen per type
TYPE_LABELS = {
    "flitser_vast": "Vaste flitser",
    "flitser_mobiel": "Mobiele flitser",
    "trajectcontrole": "Trajectcontrole",
    "politie": "Politiecontrole",
    "ongeval": "Ongeval",
    "file": "File",
    "gevaar": "Gevaar",
    "wegwerkzaamheden": "Wegwerkzaamheden",
}
TYPE_ICONS = {
    "flitser_vast": "📸",
    "flitser_mobiel": "🚨",
    "trajectcontrole": "📏",
    "politie": "🚔",
    "ongeval": "⚠️",
    "file": "🚗",
    "gevaar": "⛔",
    "wegwerkzaamheden": "🚧",
}

# === BOETE TABEL (OM Boetebase 2026) ===
FINE_TABLE = [
    (5, 45, 45, 45),
    (10, 65, 65, 65),
    (15, 95, 95, 95),
    (20, 140, 140, 140),
    (25, 180, 180, 180),
    (30, 260, 260, 260),
    (40, 380, 380, 380),
    (50, 520, 520, 520),
]

def get_db():
    """Thread-safe database connection met WAL-mode"""
    db = sqlite3.connect(str(DB_PATH), timeout=5.0, check_same_thread=False)
    db.row_factory = sqlite3.Row
    # Enable WAL-mode voor betere concurrency onder Gunicorn
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    return db

def init_db():
    """Initaliseer database schema"""
    db = get_db()
    db.execute("""
        CREATE TABLE IF NOT EXISTS reports (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            heading REAL,
            created_at REAL NOT NULL,
            expires_at REAL NOT NULL,
            confirms INTEGER DEFAULT 0,
            denies INTEGER DEFAULT 0
        )
    """)
    db.execute("CREATE INDEX IF NOT EXISTS idx_type_expires ON reports (type, expires_at)")
    db.execute("CREATE INDEX IF NOT EXISTS idx_lat_lng ON reports (lat, lng)")
    db.commit()
    logger.info("Database initialized")

def cleanup_expired(db):
    """Verwijder verlopen meldingen"""
    now = time.time()
    cursor = db.execute("DELETE FROM reports WHERE expires_at < ?", (now,))
    if cursor.rowcount > 0:
        logger.debug(f"Cleaned up {cursor.rowcount} expired reports")
    db.commit()

def haversine_km(lat1, lng1, lat2, lng2):
    """Afstand tussen twee coördinaten in km"""
    R = 6371
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlng/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

# === CORS MIDDLEWARE ===
@app.after_request
def add_cors_headers(response):
    """Voeg CORS-headers toe voor mobiele browsers"""
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return response

@app.route("/api/reports", methods=["GET"])
def get_reports():
    """Alle actieve meldingen in buurt"""
    lat = request.args.get("lat", type=float)
    lng = request.args.get("lng", type=float)
    radius_m = request.args.get("radius", default=5000, type=int)
    
    if lat is None or lng is None:
        return jsonify({"error": "lat en lng verplicht"}), 400
    
    db = get_db()
    cleanup_expired(db)
    
    radius_deg = radius_m / 111000
    rows = db.execute(
        """SELECT * FROM reports 
           WHERE lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?
           ORDER BY created_at DESC""",
        (lat - radius_deg, lat + radius_deg, lng - radius_deg, lng + radius_deg)
    ).fetchall()
    
    reports = []
    for row in rows:
        dist_km = haversine_km(lat, lng, row["lat"], row["lng"])
        if dist_km * 1000 <= radius_m:
            reports.append({
                "id": row["id"],
                "type": row["type"],
                "label": TYPE_LABELS.get(row["type"], row["type"]),
                "icon": TYPE_ICONS.get(row["type"], "⚠️"),
                "lat": row["lat"],
                "lng": row["lng"],
                "distance_m": round(dist_km * 1000),
                "confirms": row["confirms"],
                "created_at": row["created_at"],
            })
    
    logger.info(f"GET /api/reports: {len(reports)} meldingen in {radius_m}m")
    return jsonify({"reports": reports})

@app.route("/api/nearby-alert", methods=["GET"])
def nearby_alert():
    """Dichtstbijzijnde melding (voor iOS-widget)"""
    lat = request.args.get("lat", type=float)
    lng = request.args.get("lng", type=float)
    
    if lat is None or lng is None:
        return jsonify({"error": "lat en lng verplicht"}), 400
    
    db = get_db()
    cleanup_expired(db)
    
    all_reports = db.execute("SELECT * FROM reports").fetchall()
    closest = None
    closest_dist_m = float('inf')
    
    for row in all_reports:
        dist_m = haversine_km(lat, lng, row["lat"], row["lng"]) * 1000
        alert_radius = ALERT_RADIUS_M.get(row["type"], 500)
        if dist_m <= alert_radius and dist_m < closest_dist_m:
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
            "confirms": closest.get("confirms", 0),
        }
    })

@app.route("/api/reports", methods=["POST"])
def create_report():
    """Nieuwe melding aanmaken"""
    data = request.get_json(silent=True) or {}
    report_type = data.get("type")
    lat = data.get("lat")
    lng = data.get("lng")
    heading = data.get("heading")
    
    if report_type not in EXPIRY_SECONDS:
        logger.warning(f"Invalid report type: {report_type}")
        return jsonify({"error": f"Onbekend type: {report_type}"}), 400
    if lat is None or lng is None:
        return jsonify({"error": "lat en lng zijn verplicht"}), 400
    
    db = get_db()
    cleanup_expired(db)
    
    # Dedupe
    deg_margin = 0.0015
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
            logger.info(f"Confirmed existing report: {row['id']}")
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
    logger.info(f"Created report: {report_id} ({report_type})")
    return jsonify({"status": "created", "id": report_id}), 201

@app.route("/api/reports/<report_id>/vote", methods=["POST"])
def vote_report(report_id):
    """Bevestigen of ontkennen van melding"""
    data = request.get_json(silent=True) or {}
    vote = data.get("vote")
    
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
        logger.info(f"Removed report {report_id} (net_score={net_score} <= {DENY_THRESHOLD})")
        return jsonify({"status": "removed"}), 200
    
    logger.debug(f"Vote recorded: {report_id} ({vote})")
    return jsonify({"status": "ok", "confirms": updated["confirms"], "denies": updated["denies"]}), 200

@app.route("/", methods=["GET"])
def index():
    """Homepage"""
    return send_from_directory("templates", "index.html")

init_db()

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "5068"))
    debug = os.environ.get("FLITSMAATJE_DEBUG", "0").lower() in {"1", "true", "yes"}
    logger.info(f"Starting FlitsMaatje on port {port} (debug={debug})")
    app.run(host="0.0.0.0", port=port, debug=debug, use_reloader=debug)
