#!/usr/bin/env bash
# Eenmalig: GitHub-repo aanmaken, secrets zetten, TestFlight-build starten.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! gh auth status >/dev/null 2>&1; then
  echo "Eerst inloggen: gh auth login --web"
  exit 1
fi

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  echo "Gebruik: $0 GEBRUIKERSNAAM/flitsmaatje"
  echo "Voorbeeld: $0 readvanes/flitsmaatje"
  exit 1
fi

echo "==> Repo aanmaken (private)..."
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  gh repo create "${REPO#*/}" --private --source=. --remote=origin --push
else
  git remote add origin "https://github.com/${REPO}.git" 2>/dev/null || true
  git push -u origin main
fi

secrets_file="${HOME}/.flitsmaatje-secrets.env"
if [[ ! -f "$secrets_file" ]]; then
  cat > "$secrets_file" <<'EOF'
# Vul in en run dit script opnieuw
APPLE_TEAM_ID=
APPLE_ID=
ASC_KEY_ID=
ASC_ISSUER_ID=
# Base64 van je .p8 bestand (één regel, geen newlines):
ASC_KEY_CONTENT=
EOF
  chmod 600 "$secrets_file"
  echo ""
  echo "Secrets-template aangemaakt: $secrets_file"
  echo "Vul je Apple-gegevens in en run:"
  echo "  bash ios/scripts/cloud-build.sh $REPO"
  exit 0
fi

# shellcheck disable=SC1090
source "$secrets_file"
for key in APPLE_TEAM_ID APPLE_ID ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_CONTENT; do
  if [[ -z "${!key:-}" ]]; then
    echo "Ontbrekend in $secrets_file: $key"
    exit 1
  fi
done

echo "==> GitHub secrets zetten..."
gh secret set APPLE_TEAM_ID --body "$APPLE_TEAM_ID" --repo "$REPO"
gh secret set APPLE_ID --body "$APPLE_ID" --repo "$REPO"
gh secret set ASC_KEY_ID --body "$ASC_KEY_ID" --repo "$REPO"
gh secret set ASC_ISSUER_ID --body "$ASC_ISSUER_ID" --repo "$REPO"
gh secret set ASC_KEY_CONTENT --body "$ASC_KEY_CONTENT" --repo "$REPO"

echo "==> TestFlight workflow starten..."
gh workflow run testflight.yml --repo "$REPO"
echo ""
echo "Klaar! Volg de build: https://github.com/${REPO}/actions"
echo "Daarna TestFlight: https://appstoreconnect.apple.com"
