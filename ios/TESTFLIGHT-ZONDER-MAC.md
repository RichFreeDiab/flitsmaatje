# TestFlight zonder Mac

Je hebt **geen Mac nodig**. De iOS-app wordt gebouwd in de **cloud** (GitHub Actions met een macOS-server) en automatisch naar TestFlight geüpload.

## Wat jij nodig hebt

1. **Apple Developer Program** — €99/jaar → [developer.apple.com/programs](https://developer.apple.com/programs)
2. **GitHub-account** (gratis)
3. **~30 minuten** om accounts en secrets in te stellen (eenmalig)

## Stap 1 — Apple Developer + API-sleutel

1. Meld je aan bij [App Store Connect](https://appstoreconnect.apple.com)
2. Ga naar **Users and Access → Integrations → App Store Connect API**
3. Klik **+** (Generate API Key)
   - Naam: `FlitsMaatje CI`
   - Rol: **Admin** of **App Manager**
4. Download het **`.p8`-bestand** (kan maar één keer!)
5. Noteer:
   - **Key ID** (bijv. `ABC123XYZ`)
   - **Issuer ID** (bovenaan de pagina)
6. Ga naar [developer.apple.com/account](https://developer.apple.com/account) → **Membership** → noteer je **Team ID** (10 tekens)

### App Group (eenmalig, in browser)

1. [developer.apple.com/account/resources/identifiers/list/applicationGroup](https://developer.apple.com/account/resources/identifiers/list/applicationGroup) — groep `group.nl.readvanes.flitsmaatje` moet bestaan
2. Open **FlitsMaatje** (`nl.readvanes.flitsmaatje`) → vink **App Groups** aan → **Configure** → selecteer `group.nl.readvanes.flitsmaatje` → **Save**
3. Herhaal voor **FlitsMaatjeWidget** (`nl.readvanes.flitsmaatje.widget`)
4. Draai daarna opnieuw de **TestFlight** GitHub Action (profiles moeten de App Group bevatten)

> Zonder stap 2–3 faalt de build met *"doesn't support the group.nl.readvanes.flitsmaatje App Group"*.

## Stap 2 — GitHub-repository

```bash
# Op je VPS of lokaal (waar git staat):
cd /opt/flitsmaatje
git init
git add .
git commit -m "FlitsMaatje: web + iOS CarPlay widget + TestFlight CI"
```

Maak een **private** repo op GitHub (bijv. `flitsmaatje`) en push:

```bash
git remote add origin https://github.com/JOUW-GEBRUIKERSNAAM/flitsmaatje.git
git branch -M main
git push -u origin main
```

## Stap 3 — GitHub Secrets

In je repo: **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Waarde |
|--------|--------|
| `APPLE_TEAM_ID` | Je 10-tekens Team ID |
| `APPLE_ID` | Je Apple ID e-mail |
| `ASC_KEY_ID` | Key ID van de API-sleutel |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_CONTENT` | Base64 van het `.p8`-bestand (zie hieronder) |

**Base64 van .p8 maken** (in terminal, op elke computer):

```bash
base64 -w0 AuthKey_ABC123XYZ.p8
# macOS zonder -w0:
base64 -i AuthKey_ABC123XYZ.p8 | tr -d '\n'
```

Plak de hele string als `ASC_KEY_CONTENT`.

## Stap 4 — Build starten

1. GitHub repo → **Actions** → **TestFlight** → **Run workflow**
2. Wacht ~15–25 minuten (eerste build duurt langer)
3. Ga naar [App Store Connect → TestFlight](https://appstoreconnect.apple.com/apps)
4. Voeg jezelf toe als **Internal Tester** (direct beschikbaar)
5. Installeer via de **TestFlight-app** op je iPhone

## Stap 5 — CarPlay

1. Open FlitsMaatje → **Altijd** locatietoestemming
2. **Instellingen → Algemeen → CarPlay → [auto] → Widgets** → FlitsMaatje
3. Navigeer met Kaarten of Google Maps

## Kosten

| Item | Kosten |
|------|--------|
| Apple Developer | €99/jaar |
| GitHub Actions (macOS) | ~2000 min/maand gratis (private repo: beperkt; eerste builds passen meestal) |
| Mac | **€0** |

## Problemen?

| Fout | Oplossing |
|------|-----------|
| Signing failed | Controleer Team ID + App Group in Developer Portal |
| Missing compliance | App Store Connect → build → Export Compliance → "No" voor standaard HTTPS |
| Widget niet op CarPlay | iOS 26+ nodig; widget handmatig toevoegen in CarPlay-instellingen |
| Build timeout | Opnieuw runnen; Overpass/API niet nodig voor build |

## Alternatief zonder GitHub

Als je geen GitHub wilt: **Codemagic** (codemagic.io) heeft een gratis tier en een wizard voor iOS-builds zonder Mac. Upload de `ios/`-map en koppel App Store Connect API.
