# CarPlay-navigatie activeren

FlitsMaatje is gebouwd als **CarPlay-navigatie-app** (kaart op het grote autoscherm, route, flitsalarm). Daarvoor moet Apple het **CarPlay Maps**-entitlement goedkeuren.

## Status

| Stap | Status |
|------|--------|
| CarPlay-aanvraag (Navigation + 3 screenshots) | **Ingediend** — 3 jul 2026 |
| Apple-goedkeuring per e-mail | Wachten (dagen–weken) |
| CarPlay Maps App op App ID | Nog niet zichtbaar (normaal tot goedkeuring) |
| Entitlement in app + TestFlight | Na goedkeuring |

## Stap 1 — Aanvraag bij Apple ✅

Ingediend via [developer.apple.com/contact/carplay](https://developer.apple.com/contact/carplay):

- **App type:** Navigation (turn-by-turn)
- **App name:** FlitsMaatje
- **Bundle ID:** `nl.readvanes.flitsmaatje`
- **Team ID:** `D358S348HY`
- **3 screenshots:** navigatie, flitsalarm, dashboard-widget

Apple antwoordt per e-mail met goedkeuring of vragen.

## Stap 2 — App ID in Developer Portal

Na goedkeuring:

1. [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) → App ID `nl.readvanes.flitsmaatje`
2. Schakel **CarPlay Maps App** (en eventueel Dashboard) in
3. Sla op
4. Voeg in `FlitsMaatje/FlitsMaatje.entitlements` toe:

```xml
<key>com.apple.developer.carplay-maps</key>
<true/>
```

## Stap 3 — Provisioning profiles vernieuwen

1. Verwijder oude App Store-profielen voor FlitsMaatje (of laat ze verlopen)
2. Maak nieuwe profielen aan **met** CarPlay Maps-capability
3. Zorg dat Fastlane `sigh readonly` die profielen gebruikt (zoals nu)

## Stap 4 — TestFlight op je auto

1. Installeer de nieuwste TestFlight-build
2. iPhone: **Instellingen → Privacy → Locatiediensten → FlitsMaatje → Altijd**
3. Koppel iPhone aan CarPlay (kabel of draadloos)
4. Op het CarPlay-scherm: open **FlitsMaatje** (icoon tussen navigatie-apps)
5. Zoek een bestemming → **Start** → flitsers verschijnen als CarPlay-waarschuwing

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
