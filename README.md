# FlitsMaatje

Crowdsourced verkeersmeldingen-app (flitsers, politie, ongevallen, files, gevaar,
wegwerkzaamheden) met live kaart, GPS-snelheidsmeter, route-corridor alerts,
drive-context ranking en iOS/CarPlay-navigatie.
Functioneel vergelijkbaar met Flitsmeister/Waze, met eigen code en bronnen
(NDW, ANWB, TomTom, SCDB/OSM, crowdsource) — geen private Flitsmeister-backends.

## Stack
- **Backend**: Flask + SQLite
- **Web**: vanilla JS + Leaflet.js + OpenStreetMap (+ OSRM voor web-routes)
- **iOS**: MapKit turn-by-turn + CarPlay (gedeelde `DriveSession`)
- **Locatie**: browser Geolocation / CoreLocation

## Belangrijkste API's
- `GET /api/reports` — meldingen in straal
- `GET /api/nearby-alert` — gerankte alert; optioneel `route=lat,lng;...` voor corridor
- `GET /api/drive-context` — gebundelde traps / alt / incidents / jams + top alert
- `GET /api/early-warnings` — sneller kanaal voor mobiele/urgente meldingen
- `GET /api/lane-guidance` — TomTom lanes genormaliseerd naar `directionType` + `isActive`
- `GET /api/speed-check` — limiet + boete-indicatie

## Functies
1. Live kaart met positie en meldingen
2. GPS-snelheid + limiet/boete-indicatie
3. Crowdsource meldingen + stemmen
4. Route-corridor filtering (geen tegenligger/parallelweg-false positives wanneer een route actief is)
5. Ranking op afstand, heading/dual-bearing, bronprioriteit en confidence
6. Early-warning poll (~20s) naast langzamere fixed/cache refresh
7. iOS navigatie (MapKit) + CarPlay HUD met stabiele lane-strip
8. Polyline-alerts voor traject/file waar geometrie beschikbaar is
9. Web-navigatie via OSRM; iOS via MapKit (beide kunnen corridor meesturen)

## Lokaal testen
```bash
cd flitsmaatje-repo
pip install -r requirements.txt
python app.py
```
Open `http://localhost:5068`. Tests:

```bash
python -m unittest discover -s tests -v
```

## iOS
XcodeGen-project onder `ios/` (`project.yml`). Shared App Group voor widget/snapshot;
`DriveSession` deelt GPS/nav-state tussen telefoon en CarPlay.

## Deployment
Poort **5068** (gunicorn achter nginx/systemd). Zet `TOMTOM_API_KEY` voor limiet,
incidents en lane guidance. De oudere HUD-fork wordt niet meer doorontwikkeld;
alle wijzigingen horen in deze repo.

> Boete-bedragen zijn indicatief (OM Boetebase), geen juridisch advies.
