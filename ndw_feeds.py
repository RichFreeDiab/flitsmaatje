"""NDW realtime verkeersfeeds voor FlitsMaatje.

De feeds zijn DATEX-II XML in gzip. De parser is bewust tolerant: NDW kan
verschillende DATEX-II situation-records publiceren en niet elk record heeft
dezelfde tekstvelden.
"""
import gzip
import io
import re
import time
import uuid
import xml.etree.ElementTree as ET

import requests

NDW_BASE = "https://opendata.ndw.nu/"
NDW_FEEDS = {
    "actueel": "actueel_beeld.xml.gz",
    "snelheid": "tijdelijke_verkeersmaatregelen_maximum_snelheden.xml.gz",
    "veiligheid": "veiligheidsgerelateerde_berichten_srti.xml.gz",
}
NDW_TTL = 60
NDW_EXPIRY = 20 * 60
_last_sync = 0.0


def _local(tag):
    return tag.rsplit("}", 1)[-1].lower()


def _text(element):
    return " ".join(" ".join(element.itertext()).split())


def _coordinates(root):
    latitudes = []
    longitudes = []
    for element in root.iter():
        name = _local(element.tag)
        value = (element.text or "").strip()
        if not value:
            continue
        try:
            number = float(value.replace(",", "."))
        except ValueError:
            continue
        if name in {"latitude", "lat"} and -90 <= number <= 90:
            latitudes.append(number)
        elif name in {"longitude", "lon", "lng"} and -180 <= number <= 180:
            longitudes.append(number)
    if latitudes and longitudes:
        return latitudes[0], longitudes[0]
    return None


def _kind(text, feed_name):
    value = text.lower()
    if feed_name == "snelheid":
        return "gevaar"
    if any(word in value for word in ("ongeval", "aanrijding", "collision")):
        return "ongeval"
    if any(word in value for word in ("werkzaam", "afsluiting", "omleiding", "roadworks")):
        return "wegwerkzaamheden"
    if any(word in value for word in ("file", "congestie", "queue")):
        return "file"
    return "gevaar"


def _parse_feed(payload, feed_name):
    root = ET.fromstring(gzip.GzipFile(fileobj=io.BytesIO(payload)).read())
    records = []
    for element in root.iter():
        if _local(element.tag) not in {"situation", "situationrecord", "situationrecordversion"}:
            continue
        coordinate = _coordinates(element)
        if not coordinate:
            continue
        text = _text(element)
        if len(text) < 3:
            continue
        lat, lng = coordinate
        records.append((lat, lng, _kind(text, feed_name), text[:240]))
    return records


def sync_ndw_reports(db):
    """Refresh NDW-derived temporary reports at most once per minute."""
    global _last_sync
    now = time.time()
    if now - _last_sync < NDW_TTL:
        return
    _last_sync = now
    rows = []
    for feed_name, filename in NDW_FEEDS.items():
        try:
            response = requests.get(
                NDW_BASE + filename,
                timeout=12,
                headers={"User-Agent": "FlitsMaatje/1.1"},
            )
            response.raise_for_status()
            rows.extend(_parse_feed(response.content, feed_name))
        except Exception:
            # Eén onbereikbare feed mag de bestaande meldingen niet breken.
            continue

    db.execute("DELETE FROM reports WHERE id LIKE 'ndw-%'")
    expires = now + NDW_EXPIRY
    for index, (lat, lng, report_type, description) in enumerate(rows):
        report_id = f"ndw-{report_type}-{index}-{uuid.uuid4().hex[:8]}"
        db.execute(
            "INSERT INTO reports (id, type, lat, lng, heading, created_at, expires_at, confirms, denies) "
            "VALUES (?, ?, ?, ?, NULL, ?, ?, 1, 0)",
            (report_id, report_type, lat, lng, now, expires),
        )
    db.commit()
