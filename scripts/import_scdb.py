"""Import Dutch SCDB fixed speed/red-light cameras into the FlitsMaatje DB."""
import csv
import sqlite3
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "flitsmaatje.db"
# Coverage envelope for the requested countries (France, Belgium,
# Luxembourg, Germany and the Netherlands). SCDB has no country column, so
# this deliberately uses a conservative Western/Central Europe envelope.
REGION_LNG = (-5.5, 15.5)
REGION_LAT = (42.0, 55.5)
EXPIRY = 60 * 60 * 24 * 365


def in_supported_region(lng, lat):
    return REGION_LNG[0] <= lng <= REGION_LNG[1] and REGION_LAT[0] <= lat <= REGION_LAT[1]


def import_file(conn, filename, kind, known_cells):
    inserted = 0
    skipped = 0
    with filename.open(newline="", encoding="utf-8-sig", errors="replace") as handle:
        for row_number, row in enumerate(csv.reader(handle), start=1):
            if len(row) < 2:
                skipped += 1
                continue
            try:
                # SCDB exports longitude first, latitude second.
                lng, lat = float(row[0]), float(row[1])
            except ValueError:
                skipped += 1
                continue
            if not in_supported_region(lng, lat):
                skipped += 1
                continue

            cell = (round(lat, 3), round(lng, 3))
            if cell in known_cells:
                skipped += 1
                continue

            report_id = f"scdb-{kind}-{row_number}-{lat:.5f}-{lng:.5f}"
            conn.execute(
                "INSERT OR IGNORE INTO reports "
                "(id, type, lat, lng, heading, created_at, expires_at, confirms, denies) "
                "VALUES (?, 'flitser_vast', ?, ?, NULL, ?, ?, 1, 0)",
                (report_id, lat, lng, time.time(), time.time() + EXPIRY),
            )
            known_cells.add(cell)
            inserted += 1
    return inserted, skipped


def main():
    if len(sys.argv) != 3:
        raise SystemExit("gebruik: python scripts/import_scdb.py snelheid.csv roodlicht.csv")
    conn = sqlite3.connect(DB_PATH)
    try:
        known_cells = {
            (round(row[0], 3), round(row[1], 3))
            for row in conn.execute("SELECT lat, lng FROM reports WHERE type = 'flitser_vast'")
        }
        totals = [
            import_file(conn, Path(sys.argv[1]), "snelheid", known_cells),
            import_file(conn, Path(sys.argv[2]), "roodlicht", known_cells),
        ]
        conn.commit()
        print(f"snelheid: {totals[0][0]} toegevoegd, {totals[0][1]} overgeslagen")
        print(f"roodlicht: {totals[1][0]} toegevoegd, {totals[1][1]} overgeslagen")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
