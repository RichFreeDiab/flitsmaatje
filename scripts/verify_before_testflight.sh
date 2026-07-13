#!/usr/bin/env bash
# Verifieer CarPlay-gedrag + API vóór een TestFlight-deploy.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE_URL="${FLITSMAATJE_BASE_URL:-http://127.0.0.1:5068}"
STARTED_SERVER=0

cleanup() {
  if [[ "$STARTED_SERVER" == "1" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if ! curl -sf --max-time 3 "$BASE_URL/api/carplay-selftest" >/dev/null 2>&1; then
  if [[ ! -d venv ]]; then
    python3 -m venv venv
    venv/bin/pip install -q gunicorn flask requests
  fi
  echo "==> Start lokale Flask-server voor selftest..."
  venv/bin/gunicorn -b 127.0.0.1:5068 -w 1 app:app --timeout 30 >/tmp/flitsmaatje-selftest.log 2>&1 &
  SERVER_PID=$!
  STARTED_SERVER=1
  for _ in $(seq 1 20); do
    if curl -sf --max-time 2 "$BASE_URL/" >/dev/null 2>&1; then
      break
    fi
    sleep 0.5
  done
fi

echo "==> CarPlay-selftest tegen $BASE_URL"
python3 scripts/carplay_selftest.py "$BASE_URL"
echo ""
echo "==> CarPlay-demo pagina bereikbaar?"
curl -sf --max-time 5 "$BASE_URL/carplay" | grep -q "CarPlay Demo"
echo "OK: /carplay laadt"
echo ""
echo "Klaar. Open in browser: $BASE_URL/carplay"
