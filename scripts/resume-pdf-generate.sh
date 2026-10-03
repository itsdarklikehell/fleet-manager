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

# Rendert één taalversie. De taal gaat via ?lang= mee omdat Chrome hier een
# verse instantie is zonder localStorage — de pagina leest die parameter uit
# (zie applyLang in index.html).
render_lang() {
  local lang="$1" out="$2" label="$3"
  rm -f "$out"
  if ! "$CHROME" --headless=new --disable-gpu --no-sandbox --disable-dev-shm-usage \
       --user-data-dir="$TMPPROF" \
       --virtual-time-budget=15000 \
       --no-pdf-header-footer \
       --print-to-pdf="$out" \
       "http://127.0.0.1:$PORT/index.html?lang=$lang" >/dev/null 2>&1; then
    log "  ❌ Chrome-render mislukt ($label)"
    rm -f "$out"
    return 1
  fi
  if [ ! -s "$out" ]; then
    log "  ❌ PDF is leeg ($label)"
    rm -f "$out"
    return 1
  fi
  local size
  size=$(stat -c%s "$out" 2>/dev/null || echo 0)
  log "  ✅ $(basename "$out") ($label, $((size/1024)) KB)"

  # De live data moet meegerenderd zijn — anders lever je stil een leeg CV af
  if command -v pdftotext >/dev/null 2>&1; then
    if pdftotext "$out" - 2>/dev/null | grep -qi "unable to load live data"; then
      log "  ❌ PDF bevat 'Unable to load live data' — data niet meegerenderd ($label)"
      return 1
    fi
  fi
  return 0
}

OUT_PDF_EN="$RPG_REPO_DIR/$RPG_BASENAME-en.pdf"
rc=0
render_lang nl "$OUT_PDF"    "NL" || rc=1
render_lang en "$OUT_PDF_EN" "EN" || rc=1

if command -v pdftotext >/dev/null 2>&1 && [ -s "$OUT_PDF" ] && [ -s "$OUT_PDF_EN" ]; then
  log "  ✅ beide versies bevatten de live data"
fi

[ "$rc" -eq 0 ] || exit 1

log "=== Resume PDF Generate klaar ==="
