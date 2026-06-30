# FlitsMaatje iOS — Widget + Live Activity voor CarPlay

Lichte iOS-companion **zonder CarPlay-app-entitlement**. Werkt zoals Flitsmeister vroeger:
de app draait op de achtergrond voor flitswaarschuwingen, terwijl je met **Kaarten** of
**Google Maps** navigeert. Het kleine widget verschijnt op het **CarPlay Dashboard**
(iOS 26+ / CarPlay Ultra).

## Wat zit erin

| Onderdeel | Functie |
|-----------|---------|
| **Hoofdapp** | Achtergrond-GPS, pollt `https://flitsmaatje.readvanes.nl/api/nearby-alert` |
| **Widget** (`systemSmall`) | Toont dichtstbijzijnde melding — ook op CarPlay Dashboard |
| **Live Activity** | Lock Screen + Dynamic Island tijdens actieve waarschuwing |

Geen Apple CarPlay-goedkeuringsproces nodig — dit is een gewoon WidgetKit-widget.

## Vereisten

- Mac met **Xcode 16+** (iOS 17 deployment, Live Activity op CarPlay vanaf iOS 26)
- Apple Developer-account (gratis of betaald) voor installeren op je iPhone
- Optioneel: [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Project genereren (XcodeGen)

```bash
cd ios
# Vul je Team ID in project.yml onder DEVELOPMENT_TEAM
xcodegen generate
open FlitsMaatje.xcodeproj
```

## Handmatig in Xcode (zonder XcodeGen)

1. **File → New → Project → iOS App** — naam `FlitsMaatje`, bundle ID `nl.readvanes.flitsmaatje`
2. **File → New → Target → Widget Extension** — naam `FlitsMaatjeWidget`, vink **Include Live Activity** aan
3. Voeg map `Shared/` toe aan **beide** targets (Target Membership aanvinken)
4. Vervang gegenereerde bestanden door de Swift-bestanden uit deze map
5. **Signing & Capabilities** → voeg **App Groups** toe: `group.nl.readvanes.flitsmaatje` (app + widget)
6. Hoofdapp → **Background Modes**: Location updates + Audio
7. Plak `Info.plist` locatie-keys en entitlements

## App Group (verplicht)

Beide targets moeten dezelfde App Group hebben:

```
group.nl.readvanes.flitsmaatje
```

De app schrijft flitsdata naar gedeelde `UserDefaults`; het widget leest die en wordt
via `WidgetCenter.reloadTimelines` ververst.

## CarPlay instellen

1. Installeer de app op je iPhone
2. Open de app → geef **Altijd** locatietoestemming
3. Laat tracking aan staan (blauwe balk = achtergrondlocatie actief)
4. **Instellingen → Algemeen → CarPlay → [jouw auto] → Widgets**
5. Voeg **FlitsMaatje** toe aan je dashboard
6. Start navigatie met Kaarten of Google Maps in CarPlay
7. Het FlitsMaatje-widget verschijnt **naast** je navigatie-app

> Op iOS 26 verschijnen widgets links van het CarPlay Dashboard. Op oudere CarPlay-systemen
> werkt de achtergrondwaarschuwing via Live Activity (Lock Screen) en geluid.

## API

De app gebruikt:

```
GET https://flitsmaatje.readvanes.nl/api/nearby-alert?lat=52.37&lng=4.89&radius_km=15
```

Response bij waarschuwing:

```json
{
  "alert": {
    "id": "...",
    "type": "flitser_vast",
    "label": "Vaste flitser",
    "icon": "📷",
    "distance_m": 420,
    "lat": 52.37,
    "lng": 4.89,
    "confirms": 3
  }
}
```

Geen alert: `{"alert": null}`

## Testen zonder auto

1. **Simulator → CarPlay** (Xcode → I/O → External Displays → CarPlay)
2. Widget toevoegen via iPhone Simulator instellingen
3. **Debug → Simulate Location** → Custom GPX met route langs een melding

## Beperkingen (eerlijk)

- Widgets verversen niet zelfstandig op GPS — de **hoofdapp moet op de achtergrond draaien**
- iOS kan achtergrondlocatie beperken bij weinig batterij; zet FlitsMaatje uit batterijbesparing
- Zonder touchscreen in de auto is widget-interactie uitgeschakeld (alleen tonen)
- Live Activity op CarPlay vereist **iOS 26+**

## Bestandsstructuur

```
ios/
  project.yml
  Shared/           # Models, API, App Group store
  FlitsMaatje/      # Hoofdapp + achtergrondlocatie
  FlitsMaatjeWidget/ # Widget + Live Activity
```
