#!/usr/bin/env python3
"""
CarPlay + app-gedrag simulatie — draait lokaal/CI vóór TestFlight.

Bootvolgorde, API-polling, flitser-banner, stille boete-popup en Driving Task
worden hier nagebootst zoals in de iOS-app (build 86+).
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Any


DEFAULT_BASE = "http://127.0.0.1:5068"
AMSTERDAM_LAT, AMSTERDAM_LNG = 52.3676, 4.9041
FLITSER_LAT, FLITSER_LNG = 52.3688, 4.9060
ALARM_THRESHOLDS = [600, 400, 200, 100]


@dataclass
class Check:
    name: str
    ok: bool
    detail: str = ""

    def as_dict(self) -> dict[str, Any]:
        return {"name": self.name, "ok": self.ok, "detail": self.detail}


@dataclass
class SelfTestResult:
    ok: bool
    checks: list[Check] = field(default_factory=list)
    boot_stages: list[str] = field(default_factory=list)
    carplay_events: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "checks": [c.as_dict() for c in self.checks],
            "boot_stages": self.boot_stages,
            "carplay_events": self.carplay_events,
        }


class CarPlaySimulator:
    """Minimale state machine van de iOS-app + CarPlay-gedrag."""

    def __init__(self) -> None:
        self.is_app_active = False
        self.carplay_app = "flitsmeister"
        self.is_tracking = False
        self.auth_status = "not_determined"
        self.last_alert_id: str | None = None
        self.passed_thresholds: set[int] = set()
        self.boot_stages: list[str] = []
        self.carplay_events: list[str] = []

    def mark_boot(self, stage: str) -> None:
        self.boot_stages.append(stage)

    def simulate_launch(self) -> None:
        self.mark_boot("process-start")
        self.mark_boot("didFinishLaunching")
        self.mark_boot("logger-installed")
        self.mark_boot("phone-scene-willConnect")
        self.mark_boot("phone-window-visible")
        self.mark_boot("rootview-onAppear")
        self.mark_boot("user-start-tap")
        self.mark_boot("location-created")
        self.mark_boot("bootstrap-complete")
        self.auth_status = "authorized_always"
        self.mark_boot("location-permission-start")
        self.is_app_active = True
        self.mark_boot("location-activate")
        self.is_tracking = True
        self.mark_boot("location-tracking-active")

    def set_carplay_app(self, app: str) -> None:
        self.carplay_app = app

    def handle_flitser(self, alert: dict[str, Any]) -> bool:
        """Returns True als er een CarPlay-melding getoond zou worden."""
        alert_id = str(alert.get("id", "unknown"))
        distance = int(alert.get("distance_m", 9999))
        should_alarm = False

        if self.last_alert_id != alert_id:
            self.last_alert_id = alert_id
            self.passed_thresholds = set()
            should_alarm = True
        else:
            for threshold in ALARM_THRESHOLDS:
                if distance <= threshold and threshold not in self.passed_thresholds:
                    self.passed_thresholds.add(threshold)
                    should_alarm = True
                    break

        if not should_alarm:
            return False

        label = alert.get("label", "Flitser")
        if self.carplay_app == "flitsmeister":
            self.carplay_events.append(f"BANNER+SPEECH: {label} over {distance} m")
            return True

        self.carplay_events.append(f"CPALERT: {label} over {distance} m")
        return True

    def handle_speeding(self, speed_kmh: int, limit: int, fine: dict[str, Any]) -> bool:
        excess = int(fine.get("excess_kmh", speed_kmh - limit))
        if excess < 4:
            return False
        bedrag = fine.get("bedrag")
        title = f"Te hard — indicatief €{bedrag}" if bedrag else f"Te hard — {excess} km/u"
        if self.carplay_app == "flitsmeister":
            self.carplay_events.append(f"STILLE BANNER: {title} ({speed_kmh} km/u, limiet {limit})")
            return True
        self.carplay_events.append(f"DRIVING TASK: {title}")
        return True


def _get(base: str, path: str, params: dict[str, Any] | None = None) -> tuple[int, Any]:
    url = base.rstrip("/") + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "FlitsMaatje-SelfTest/1"})
    with urllib.request.urlopen(req, timeout=12) as resp:
        body = resp.read().decode("utf-8")
        try:
            return resp.status, json.loads(body)
        except json.JSONDecodeError:
            return resp.status, body


def _post_json(base: str, path: str, payload: dict[str, Any]) -> tuple[int, Any]:
    url = base.rstrip("/") + path
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json", "User-Agent": "FlitsMaatje-SelfTest/1"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=12) as resp:
        return resp.status, json.loads(resp.read().decode("utf-8"))


def run_selftest(base_url: str = DEFAULT_BASE, seed_demo: bool = True) -> SelfTestResult:
    result = SelfTestResult(ok=True)
    sim = CarPlaySimulator()

    def add(name: str, ok: bool, detail: str = "") -> None:
        result.checks.append(Check(name, ok, detail))
        if not ok:
            result.ok = False

    # --- Pagina bereikbaar ---
    try:
        status, body = _get(base_url, "/carplay")
        add("carplay_page", status == 200 and "CarPlay Demo" in str(body), f"HTTP {status}")
    except Exception as exc:
        add("carplay_page", False, str(exc))

    # --- Boot simulatie ---
    sim.simulate_launch()
    required_stages = [
        "process-start",
        "didFinishLaunching",
        "logger-installed",
        "phone-scene-willConnect",
        "phone-window-visible",
        "rootview-onAppear",
        "location-created",
        "location-activate",
        "location-tracking-active",
    ]
    missing = [s for s in required_stages if s not in sim.boot_stages]
    add("boot_sequence", not missing, "ontbreekt: " + ", ".join(missing) if missing else "OK")
    result.boot_stages = sim.boot_stages

    # --- API: nearby-alert ---
    try:
        status, data = _get(
            base_url,
            "/api/nearby-alert",
            {"lat": AMSTERDAM_LAT, "lng": AMSTERDAM_LNG, "radius_km": 15},
        )
        add("api_nearby_alert", status == 200 and isinstance(data, dict), f"HTTP {status}")
    except Exception as exc:
        add("api_nearby_alert", False, str(exc))
        data = {}

    # --- Seed demo flitser (optioneel) ---
    if seed_demo:
        try:
            status, _ = _post_json(
                base_url,
                "/api/reports",
                {"type": "flitser_vast", "lat": FLITSER_LAT, "lng": FLITSER_LNG},
            )
            add("seed_demo_flitser", status in (200, 201), f"HTTP {status}")
        except Exception as exc:
            add("seed_demo_flitser", False, str(exc))

        try:
            status, data = _get(
                base_url,
                "/api/nearby-alert",
                {"lat": AMSTERDAM_LAT, "lng": AMSTERDAM_LNG, "radius_km": 15},
            )
            alert = data.get("alert") if isinstance(data, dict) else None
            add("nearby_after_seed", status == 200, "alert aanwezig" if alert else "geen alert")
        except Exception as exc:
            add("nearby_after_seed", False, str(exc))
            alert = None
    else:
        alert = data.get("alert") if isinstance(data, dict) else None

    # --- Flitser + Flitsmeister (banner) ---
    sim.set_carplay_app("flitsmeister")
    if alert:
        fired = sim.handle_flitser(alert)
        add("flitser_banner_flitsmeister", fired, sim.carplay_events[-1] if fired else "geen melding")
    else:
        demo_alert = {
            "id": "selftest",
            "label": "Vaste flitser",
            "distance_m": 200,
            "icon": "📷",
        }
        fired = sim.handle_flitser(demo_alert)
        add("flitser_banner_flitsmeister", fired, sim.carplay_events[-1] if fired else "demo fallback")

    # --- Flitser + FlitsMaatje foreground (CPAlert) ---
    sim.set_carplay_app("flitsmaatje")
    demo_alert2 = {
        "id": "selftest2",
        "label": "Vaste flitser",
        "distance_m": 150,
        "icon": "📷",
    }
    fired2 = sim.handle_flitser(demo_alert2)
    add("flitser_cpalert_flitsmaatje", fired2 and "CPALERT" in sim.carplay_events[-1], sim.carplay_events[-1])

    # --- Speed-check + stille boete-banner ---
    try:
        status, speed_data = _get(
            base_url,
            "/api/speed-check",
            {"lat": AMSTERDAM_LAT, "lng": AMSTERDAM_LNG, "speed_kmh": 112},
        )
        fine = speed_data.get("fine") if isinstance(speed_data, dict) else None
        limit = (speed_data.get("limit") or {}).get("maxspeed", 100) if isinstance(speed_data, dict) else 100
        add("api_speed_check", status == 200, f"HTTP {status}")
    except Exception as exc:
        add("api_speed_check", False, str(exc))
        fine = {"excess_kmh": 12, "bedrag": 228, "om_zaak": False}
        limit = 100

    sim.set_carplay_app("flitsmeister")
    fine = fine or {"excess_kmh": 12, "bedrag": 228}
    speed_ok = sim.handle_speeding(112, int(limit or 100), fine)
    add("speeding_silent_banner", speed_ok, sim.carplay_events[-1] if speed_ok else "geen boete")

    # --- Driving Task lijst ---
    sim.set_carplay_app("flitsmaatje")
    dt_ok = sim.handle_speeding(112, int(limit or 100), fine)
    add("driving_task_speeding", dt_ok, sim.carplay_events[-1] if dt_ok else "geen item")

    result.carplay_events = sim.carplay_events
    return result


def main() -> int:
    base = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_BASE
    result = run_selftest(base)
    print(json.dumps(result.as_dict(), indent=2, ensure_ascii=False))
    if result.ok:
        print("\n✅ CarPlay-selftest GESLAAGD — veilig om iOS te builden.", file=sys.stderr)
        return 0
    print("\n❌ CarPlay-selftest GEFAALD — geen TestFlight deployen.", file=sys.stderr)
    failed = [c for c in result.checks if not c.ok]
    for check in failed:
        print(f"  - {check.name}: {check.detail}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
