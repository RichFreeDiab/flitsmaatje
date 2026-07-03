#!/usr/bin/env python3
"""Genereer hoge-kwaliteit CarPlay-screenshots voor Apple-aanvraag."""

from pathlib import Path

from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:5068/carplay-submit"
OUT = Path(__file__).resolve().parents[1] / "static" / "carplay-submit"

SCENES = [
    ("nav", "flitsmaatje-carplay-1.jpg", "Turn-by-turn navigatie op A2"),
    ("search", "flitsmaatje-carplay-2.jpg", "Bestemming zoeken"),
    ("alert", "flitsmaatje-carplay-3.jpg", "Flitser-waarschuwing tijdens rijden"),
]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(
            viewport={"width": 1920, "height": 720},
            device_scale_factor=2,
        )

        for scene, filename, _label in SCENES:
            page.goto(f"{BASE}?scene={scene}", wait_until="networkidle")
            page.wait_for_selector("body.ready", timeout=15000)
            page.wait_for_timeout(2000)
            target = OUT / filename
            page.screenshot(path=str(target), type="jpeg", quality=95)
            print(f"Wrote {target} ({target.stat().st_size // 1024} KB)")

        browser.close()


if __name__ == "__main__":
    main()
