#!/usr/bin/env python3
"""Genereer een minimaal 1024x1024 app-icoon (vereist voor TestFlight)."""
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "FlitsMaatje/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
OUT.parent.mkdir(parents=True, exist_ok=True)

size = 1024
img = Image.new("RGB", (size, size), "#1a1a2e")
draw = ImageDraw.Draw(img)

# Rode waarschuwingscirkel
margin = 80
draw.ellipse([margin, margin, size - margin, size - margin], fill="#e63946", outline="#ffffff", width=12)

# Camera-icoon (vereenvoudigd)
cx, cy = size // 2, size // 2
draw.rounded_rectangle([cx - 200, cy - 120, cx + 200, cy + 120], radius=30, fill="#1a1a2e")
draw.ellipse([cx - 90, cy - 90, cx + 90, cy + 90], outline="#ffffff", width=14)
draw.ellipse([cx - 40, cy - 40, cx + 40, cy + 40], fill="#ffffff")
draw.rectangle([cx + 120, cy - 80, cx + 180, cy - 20], fill="#1a1a2e")

img.save(OUT, "PNG")
print(f"Icon geschreven: {OUT}")
