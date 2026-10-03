#!/usr/bin/env bash
# resume-pdf-generate.sh - Bouw een eigen PDF van de CV-pagina
#
# Waarom: de "Download PDF"-knop wees naar een externe canva.link die kan
# verlopen. Deze stap genereert de PDF uit de eigen pagina (de print-stylesheet
# in index.html is daar al op ingericht) en zet hem in de repo.
#
# Gebruik:
#   bash scripts/resume-pdf-generate.sh [--dry-run]
#
# Env:
#   RPG_REPO_DIR   git-clone met index.html (default: scratch/itsdarklikehell-my-resume)
#   RPG_BASENAME   bestandsnaam zonder extensie (default: bauke-molenaar-cv)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/config.sh
source "$SCRIPT_DIR/../lib/config.sh"

RPG_DRY_RUN="no"
[ "${1:-}" = "--dry-run" ] && RPG_DRY_RUN="yes"
[ "${GITHUB_FLEET_DRY_RUN:-}" != "" ] && RPG_DRY_RUN="yes"

RPG_REPO_DIR="${RPG_REPO_DIR:-$HOME/.hermes/cache/scratch/itsdarklikehell-my-resume}"
RPG_BASENAME="${RPG_BASENAME:-bauke-molenaar-cv}"

CHROME=""
for c in google-chrome google-chrome-stable chromium chromium-browser; do
  if command -v "$c" >/dev/null 2>&1; then CHROME="$c"; break; fi
done

log "=== Resume PDF Generate ==="

if [ -z "$CHROME" ]; then
  log "❌ geen Chrome/Chromium gevonden — PDF-generatie overgeslagen"
  exit 1
fi
if [ ! -f "$RPG_REPO_DIR/index.html" ]; then
  log "❌ index.html niet gevonden in $RPG_REPO_DIR"
  exit 1
fi

OUT_PDF="$RPG_REPO_DIR/$RPG_BASENAME.pdf"

if [ "$RPG_DRY_RUN" = "yes" ]; then
  log "  🔒 [DRY-RUN] zou PDF genereren naar $OUT_PDF met $CHROME"
  log "=== Resume PDF Generate klaar (dry-run) ==="
  exit 0
fi

# Render de lokale pagina naar PDF. --print-to-pdf respecteert @media print,
# dus de knoppen/toggles verdwijnen automatisch.
#
# BELANGRIJK: via file:// blokkeert Chrome de fetch() naar github-data.json
# (CORS), waardoor de PDF "Unable to load live data" toont. Daarom serveren we
# de map eerst via een lokale HTTP-server.
log "  Renderen met $CHROME..."
TMPPROF=$(mktemp -d)
trap 'rm -rf "$TMPPROF"' EXIT

PORT=$(python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()")
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$RPG_REPO_DIR" >/dev/null 2>&1 &
SRV_PID=$!
trap 'rm -rf "$TMPPROF"; kill $SRV_PID 2>/dev/null || true' EXIT

# Wacht tot de server luistert (max 5s) — geen blinde sleep
for i in $(seq 1 50); do
  if python3 -c "
import socket,sys
s=socket.socket(); s.settimeout(0.1)
sys.exit(0 if s.connect_ex(('127.0.0.1',$PORT))==0 else 1)
" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

if "$CHROME" --headless=new --disable-gpu --no-sandbox --disable-dev-shm-usage \
     --user-data-dir="$TMPPROF" \
     --virtual-time-budget=15000 \
     --no-pdf-header-footer \
     --print-to-pdf="$OUT_PDF" \
     "http://127.0.0.1:$PORT/index.html" >/dev/null 2>&1; then
  if [ -s "$OUT_PDF" ]; then
    size=$(stat -c%s "$OUT_PDF" 2>/dev/null || echo 0)
    log "  ✅ PDF gegenereerd: $RPG_BASENAME.pdf ($((size/1024)) KB)"
  else
    log "  ❌ PDF is leeg"
    rm -f "$OUT_PDF"
    exit 1
  fi
else
  log "  ❌ Chrome-render mislukt"
  rm -f "$OUT_PDF"
  exit 1
fi

# Verifieer dat de live data meegerenderd is (geen "Unable to load" in de PDF)
if command -v pdftotext >/dev/null 2>&1; then
  if pdftotext "$OUT_PDF" - 2>/dev/null | grep -qi "unable to load live data"; then
    log "  ❌ PDF bevat 'Unable to load live data' — data is niet meegerenderd"
    exit 1
  fi
  log "  ✅ PDF bevat de live data"
fi

# Pagina moet naar de eigen PDF wijzen i.p.v. de externe link
if grep -q 'canva.link' "$RPG_REPO_DIR/index.html"; then
  python3 - "$RPG_REPO_DIR/index.html" "$RPG_BASENAME.pdf" <<'PY'
import re, sys
path, pdfname = sys.argv[1], sys.argv[2]
src = open(path).read()
src = re.sub(r'href="https://canva\.link/[^"]*"', f'href="{pdfname}" download', src)
open(path, 'w').write(src)
print(f"  ✅ Download-knop wijst nu naar {pdfname}")
PY
fi

log "=== Resume PDF Generate klaar ==="
