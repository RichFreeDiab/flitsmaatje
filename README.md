# FlitsMaatje — MVP

Crowdsourced verkeersmeldingen-app (flitsers, politie, ongevallen, files, gevaar,
wegwerkzaamheden) met live kaart, GPS-snelheidsmeter en proximity-waarschuwingen.
Functioneel vergelijkbaar met Flitsmeister/Waze, met eigen code (geen Flitsmeister-
broncode gebruikt — die is niet open source).

## Stack
- **Backend**: Flask + SQLite (zelfde patroon als je andere Flask-apps op de VPS)
- **Frontend**: vanilla JS + Leaflet.js + OpenStreetMap tiles (geen API-key nodig)
- **Locatie**: browser Geolocation API (watchPosition), werkt op mobiel en desktop

## Functies in deze MVP
1. **Live kaart** met je eigen positie, gecentreerd en volgend
2. **GPS-snelheidsmeter** (km/h), gebruikt `coords.speed` indien beschikbaar,
   anders berekend uit positie-delta's
3. **Meldingen plaatsen** via de rode ➕ knop: vaste flitser, mobiele flitser,
   trajectcontrole, politie, ongeval, file, gevaar, wegwerkzaamheden
4. **Crowdsourcing**: meldingen in de buurt van een bestaande melding tellen als
   bevestiging i.p.v. een dubbele marker; gebruikers kunnen "nog aanwezig" of
   "niet meer aanwezig" stemmen. Bij genoeg "weg"-stemmen verdwijnt de melding
5. **Automatisch verlopen**: elk type heeft een eigen vervaltermijn (mobiele
   flitser 2u, ongeval 3u, vaste flitser ~permanent, etc. — instelbaar in `app.py`)
6. **Proximity-alert**: banner + geluidssignaal als je een melding nadert
   (afstand per type instelbaar in `static/js/app.js`)
7. **Snelheidslimiet + boete-indicatie**: haalt via de gratis Overpass API
   (OpenStreetMap) de geldende limiet op je locatie op, vergelijkt die met je
   GPS-snelheid, en toont — als je te hard rijdt — een indicatieve boete op
   basis van de CJIB/OM Boetebase-tarieven van 2026. Inclusief de gangbare
   meetcorrectie (3 km/u tot 100 km/u, daarboven 3%) en het onderscheid
   bebouwde kom / buiten bebouwde kom / snelweg, met OM-dagvaarding-melding
   bij forse overschrijdingen i.p.v. een vast bedrag.

   ⚠️ **Dit is een indicatie, geen juridisch advies.** De boetebedragen zijn
   handmatig overgenomen uit de OM Boetebase 2026 (tussen de bekende
   staffelpunten wordt lineair geïnterpoleerd) en de snelheidslimiet komt uit
   OpenStreetMap-data, die kan verouderd of onvolledig zijn. Bij ontbrekende
   `maxspeed`-tags valt de app terug op een vuistregel per wegtype. De enige
   bindende bron voor de geldende limiet is de bebording ter plaatse.

## Lokaal testen
```bash
cd flitsmaatje
pip install -r requirements.txt --break-system-packages
python app.py
```
Open daarna `http://localhost:5065` op je telefoon (zelfde wifi-netwerk) of
desktop. Voor GPS op mobiel via http (niet https) moet je telefoon en server
op hetzelfde netwerk zitten en de browser toestaan locatie te delen — sommige
mobiele browsers vereisen https voor geolocation, zie Productie-sectie.

## Deployment op je Contabo VPS
Je gebruikt al poorten 5057–5064 voor je andere Flask-apps, dus **poort 5065**
is hier gereserveerd (instelbaar onderin `app.py`).

```bash
# Op de VPS
cd /pad/naar/apps
git clone <jouw-repo> flitsmaatje   # of scp de map omhoog
cd flitsmaatje
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Test
python app.py
```

Voor productie: zet 'm achter gunicorn + een systemd service, zoals je
waarschijnlijk al doet voor HealthHub/NutriScan:

```ini
# /etc/systemd/system/flitsmaatje.service
[Unit]
Description=FlitsMaatje
After=network.target

[Service]
WorkingDirectory=/pad/naar/apps/flitsmaatje
ExecStart=/pad/naar/apps/flitsmaatje/venv/bin/gunicorn -w 2 -b 127.0.0.1:5068 app:app --timeout 30
Restart=always

[Install]
WantedBy=multi-user.target
```

En een Nginx reverse proxy entry zoals je vermoedelijk al voor de andere apps
hebt, met een subdomein zoals `flits.vanesseo.nl` → `127.0.0.1:5065`.

**Belangrijk:** browsers staan GPS (`navigator.geolocation`) alleen toe over
**https**, behalve op `localhost`. Zorg dus voor een Let's Encrypt cert via
Certbot op het subdomein voordat de app op straat z'n nut heeft.

## Bekende beperkingen / volgende stappen
- **Overpass API is gratis maar rate-limited** en soms traag (1-3s per call
  bij drukte). De backend cachet resultaten 2 minuten per ~11m-gridcel om dit
  te beperken; bij zwaar gebruik kun je overwegen een eigen Overpass-instance
  te draaien of over te stappen op een betaalde routing/maxspeed-API.
- **Boetetabel is handmatig ingevoerd** uit de OM Boetebase 2026 en wordt niet
  automatisch bijgewerkt. Check jaarlijks (boetes wijzigen meestal per
  1 januari) of de tabel in `FINE_TABLE` in `app.py` nog klopt.
- **Geen navigatie/routing** — puur meldingen + kaart, geen turn-by-turn.
- **Proximity-check is afstand-only**, geen rijrichting-filter — je krijgt ook
  een melding voor iets aan de andere kant van de weg of achter je. Met
  `heading` (rijrichting, al opgeslagen in de database) kan dit verfijnd worden.
- **Geen gebruikersaccounts** — alle meldingen zijn anoniem, geen reputatiesysteem.
- **SQLite** is prima voor een MVP/prototype; bij serieus gebruik met meerdere
  gelijktijdige schrijvers kun je naar Postgres migreren (zelfde patroon als
  je LocalPulse-schema).
- **Native app**: zodra de webversie werkt zoals je wilt, kan dit met Capacitor
  of React Native ingepakt worden tot een installeerbare iOS/Android app,
  inclusief achtergrond-GPS (wat in de browser beperkt werkt zodra het scherm uitgaat).
