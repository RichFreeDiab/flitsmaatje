# CarPlay-navigatie activeren

FlitsMaatje is gebouwd als **CarPlay-navigatie-app** (kaart op het grote autoscherm, route, flitsalarm). Daarvoor moet Apple het **CarPlay Maps**-entitlement goedkeuren.

## Stap 1 — Aanvraag bij Apple

1. Ga naar [developer.apple.com/contact/carplay](https://developer.apple.com/contact/carplay)
2. Kies **Navigation** als app-categorie
3. Vul in:
   - **App name:** FlitsMaatje
   - **Bundle ID:** `nl.readvanes.flitsmaatje`
   - **Team ID:** `D358S348HY`
   - **Beschrijving:** Navigatie-app met flitsers, snelheidscontrole en boete-indicatie voor Nederland
4. Wacht op goedkeuring (meestal enkele dagen tot weken)

## Stap 2 — App ID in Developer Portal

Na goedkeuring:

1. [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) → App ID `nl.readvanes.flitsmaatje`
2. Schakel **CarPlay Maps App** (en eventueel Dashboard) in
3. Sla op

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
