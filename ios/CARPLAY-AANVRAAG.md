# CarPlay Driving Task activeren

FlitsMaatje is gebouwd als **CarPlay Driving Task app** (glanceable lijst + alert bij flitsers). Hiervoor is het **CarPlay Driving Task** entitlement nodig.

## Status

| Stap | Status |
|------|--------|
| Aanvraag ingediend | ✅ (initieel als Navigation) — 3 jul 2026 |
| Apple-toewijzing Driving Task entitlement | ✅ **Toegekend** — 9 jul 2026 (Case-ID `20858474`) |
| Capability op App ID geactiveerd + nieuwe profielen | Te doen (Developer Portal) |
| Entitlement in app + TestFlight | Na nieuwe profielen |

## Stap 1 — Apple-entitlement toegekend ✅

Apple Developer Relations heeft bevestigd dat **CarPlay Driving Task** aan het account is toegewezen (Case-ID `20858474`).

Belangrijk: FlitsMaatje is **geen Navigation app** (geen routeplanning, geen turn-by-turn, geen zoek/browse van locaties). De CarPlay UI gebruikt Driving Task templates: **lijst + alert**.

## Stap 2 — App ID in Developer Portal

Nu (na toewijzing):

1. [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) → App ID `nl.readvanes.flitsmaatje`
2. Schakel **CarPlay Driving Task App** in
3. Sla op
4. Voeg in `FlitsMaatje/FlitsMaatje.entitlements` toe:

```xml
<key>com.apple.developer.carplay-driving-task</key>
<true/>
```

## Stap 3 — Provisioning profiles vernieuwen

1. Verwijder oude App Store-profielen voor FlitsMaatje (of laat ze verlopen)
2. Maak nieuwe profielen aan **met** CarPlay Driving Task capability
3. Zorg dat Fastlane `sigh readonly` die profielen gebruikt (zoals nu)

## Stap 4 — TestFlight op je auto

1. Installeer de nieuwste TestFlight-build
2. iPhone: **Instellingen → Privacy → Locatiediensten → FlitsMaatje → Altijd**
3. Koppel iPhone aan CarPlay (kabel of draadloos)
4. Op het CarPlay-scherm: open **FlitsMaatje** (icoon tussen CarPlay-apps)
5. Je ziet een **lijst** met de dichtstbijzijnde melding en krijgt een **alert** bij nadering

## Tot Apple goedkeurt

Zonder entitlement zie je FlitsMaatje **niet** als navigatie-app op CarPlay. Wel werkt al:

- **CarPlay Dashboard-widget** (iOS 26+): Instellingen → CarPlay → [auto] → Widgets → FlitsMaatje
- **Live Activity** op het dashboard bij een flitser in de buurt
- **Flitsalarm** (geluid + trilling) op de iPhone

## Simulator (zonder auto)

Op een Mac met Xcode:

```bash
# CarPlay Simulator (Xcode → Open Developer Tool → CarPlay Simulator)
# Koppel aan de FlitsMaatje-simulator-build
```

Of gebruik de web-preview: `https://flitsmaatje.readvanes.nl/carplay`
