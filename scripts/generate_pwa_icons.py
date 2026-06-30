#!/usr/bin/env python3
"""Genereer PWA-iconen voor de webapp."""
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    import subprocess
    subprocess.check_call(["pip3", "install", "pillow", "-q"])
    from PIL import Image, ImageDraw

OUT_DIR = Path(__file__).resolve().parent.parent / "static/icons"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def make_icon(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size), "#1a1a2e")
    draw = ImageDraw.Draw(img)
    m = size // 8
    draw.ellipse([m, m, size - m, size - m], fill="#e63946", outline="#ffffff", width=max(2, size // 85))
    cx, cy = size // 2, size // 2
    r = size // 8
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline="#ffffff", width=max(2, size // 100))
    return img


for s in (192, 512):
    make_icon(s).save(OUT_DIR / f"icon-{s}.png", "PNG")
    print(f"Geschreven: {OUT_DIR / f'icon-{s}.png'}")
