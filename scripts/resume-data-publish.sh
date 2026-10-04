#!/usr/bin/env bash
# resume-data-publish.sh - Publiceer gegenereerde profieldata naar de git-repo
#
# Waarom dit bestaat: profile-data-generator.sh schrijft de JSON naar
# $REPOS_DIR (een werk-map zonder git). Zonder deze stap blijft de
# GitHub Pages-site dus op verouderde data staan. Dit script is de
# sluitende schakel: kopieer -> valideer -> commit -> push.
#
# Gebruik:
#   bash scripts/resume-data-publish.sh [--dry-run]
#
# Env:
#   RDP_REPO_DIR    pad naar de git-clone (default: scratch/itsdarklikehell-my-resume)
#   RDP_SOURCE_DIR  pad naar de gegenereerde JSON (default: $REPOS_DIR/itsdarklikehell-my-resume)
#   RDP_BRANCH      branch (default: main)

set -euo pipefail
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/config.sh
source "$SCRIPT_DIR/../lib/config.sh"

RDP_DRY_RUN="no"
[ "${1:-}" = "--dry-run" ] && RDP_DRY_RUN="yes"
[ "${GITHUB_FLEET_DRY_RUN:-}" != "" ] && RDP_DRY_RUN="yes"

RDP_REPO_DIR="${RDP_REPO_DIR:-$HOME/.hermes/cache/scratch/itsdarklikehell-my-resume}"
RDP_SOURCE_DIR="${RDP_SOURCE_DIR:-$REPOS_DIR/itsdarklikehell-my-resume}"
RDP_BRANCH="${RDP_BRANCH:-main}"

log "=== Resume Data Publish ==="
log "  bron:  $RDP_SOURCE_DIR"
log "  doel:  $RDP_REPO_DIR"

# --- Checks ---------------------------------------------------------------
if [ ! -d "$RDP_SOURCE_DIR" ]; then
  if [ "$RDP_DRY_RUN" = "yes" ]; then
    log "⚠️ bron-map bestaat niet: $RDP_SOURCE_DIR — overgeslagen (dry-run)"
    exit 0
  fi
  log "❌ bron-map bestaat niet: $RDP_SOURCE_DIR"
  exit 1
fi
if [ ! -d "$RDP_REPO_DIR/.git" ]; then
  log "❌ doel is geen git-repo: $RDP_REPO_DIR"
  exit 1
fi

for f in github-data.json profile-data.json; do
  if [ ! -s "$RDP_SOURCE_DIR/$f" ]; then
    log "❌ bronbestand ontbreekt of is leeg: $RDP_SOURCE_DIR/$f"
    exit 1
  fi
done

# De PDF wordt in de repo zelf gegenereerd (niet in $REPOS_DIR), dus die
# controleren we op de doellocatie. Ontbreken is geen fout: dan is er nog
# geen PDF gemaakt.
RDP_PDFS=()
for cand in "$RDP_REPO_DIR"/*.pdf; do
  [ -f "$cand" ] && RDP_PDFS+=("$(basename "$cand")")
done

# --- Valideer de bron-JSON vóór we iets aanraken -------------------------
validate_json() {
  python3 - "$1" <<'PY' 2>/dev/null
import json, sys
path = sys.argv[1]
with open(path) as f:
    d = json.load(f)
name = path.rsplit('/', 1)[-1]
if name == 'github-data.json':
    s = d.get('stats') or {}
    inner = s.get('stats') or {}
    repos = s.get('repos')
    assert isinstance(repos, list) and repos, 'repos ontbreekt of is leeg'
    expected = sum(r.get('stars', 0) for r in repos)
    got = inner.get('total_stars', 0)
    assert got == expected, f'total_stars {got} != som {expected}'
    assert inner.get('total_repos', 0) == len(repos), 'total_repos != len(repos)'
    # Origineel vs fork moet consistent zijn met de repo-lijst
    forks = [r for r in repos if r.get('fork')]
    own = [r for r in repos if not r.get('fork')]
    assert inner.get('fork_repos', -1) == len(forks), f"fork_repos != {len(forks)}"
    assert inner.get('own_repos', -1) == len(own), f"own_repos != {len(own)}"
    assert inner.get('own_stars', -1) == sum(r.get('stars', 0) for r in own), 'own_stars klopt niet'
    assert inner.get('fork_stars', -1) == sum(r.get('stars', 0) for r in forks), 'fork_stars klopt niet'
    # Skills mogen alleen originele talen bevatten
    assert inner.get('languages', 0) > 0, 'languages is 0'
    assert isinstance(s.get('skills'), dict) and s['skills'], 'skills ontbreekt'
    assert isinstance(s.get('contributions'), list), 'contributions ontbreekt'
else:
    for key in ('tryhackme', 'hackthebox', 'cylab'):
        assert key in d, f'{key} ontbreekt'
PY
}

for f in github-data.json profile-data.json; do
  if ! validate_json "$RDP_SOURCE_DIR/$f"; then
    log "❌ validatie mislukt voor $f — publicatie afgebroken"
    exit 1
  fi
  log "  ✅ $f gevalideerd"
done

# --- Kopieer en check of er iets veranderd is ---------------------------
changed=0
# PDF's: alleen melden dat ze meegaan, niet kopieren (staan al in de repo)
if [ "${#RDP_PDFS[@]}" -gt 0 ]; then
  for _pdf in "${RDP_PDFS[@]}"; do
    git -C "$RDP_REPO_DIR" status --porcelain "$_pdf" 2>/dev/null | grep -q . && changed=1
  done
fi

for f in github-data.json profile-data.json; do
  if ! cmp -s "$RDP_SOURCE_DIR/$f" "$RDP_REPO_DIR/$f" 2>/dev/null; then
    cp "$RDP_SOURCE_DIR/$f" "$RDP_REPO_DIR/$f"
    log "  📄 $f bijgewerkt"
    changed=1
  fi
done

if [ "$changed" -eq 0 ]; then
  log "  ℹ️  geen wijzigingen — niets te publiceren"
  log "=== Resume Data Publish klaar (no-op) ==="
  exit 0
fi

if [ "$RDP_DRY_RUN" = "yes" ]; then
  log "  🔒 [DRY-RUN] zou committen en pushen naar $RDP_BRANCH"
  log "=== Resume Data Publish klaar (dry-run) ==="
  exit 0
fi

# --- Commit + push ------------------------------------------------------
cd "$RDP_REPO_DIR" || { log "❌ kan niet naar $RDP_REPO_DIR"; exit 1; }

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  git add github-data.json profile-data.json 2>/dev/null || true
  # Social-preview-kaart meenemen als die bestaat
  [ -f "$RDP_REPO_DIR/og-image.png" ] && git add og-image.png 2>/dev/null || true
  # Beide PDF's meenemen (NL + EN) als ze bestaan
  if [ "${#RDP_PDFS[@]}" -gt 0 ]; then
    for _pdf in "${RDP_PDFS[@]}"; do git add "$_pdf" 2>/dev/null || true; done
  fi
  git commit -m "chore(data): profieldata automatisch bijgewerkt

Gegenereerd door profile-data-generator.sh en gepubliceerd door
resume-data-publish.sh. $(date -u '+%Y-%m-%dT%H:%M:%SZ')" >/dev/null 2>&1 || true

  # Rebase tegen remote om niet te stranden op een divergerende branch
  git pull --rebase origin "$RDP_BRANCH" >/dev/null 2>&1 || true

  if git push origin "$RDP_BRANCH" >/dev/null 2>&1; then
    log "  ✅ gepusht naar origin/$RDP_BRANCH"
  else
    log "  ❌ push mislukt (remote niet bereikbaar of conflict)"
    exit 1
  fi
else
  log "  ℹ️  geen git-wijzigingen"
fi

log "=== Resume Data Publish klaar ==="
