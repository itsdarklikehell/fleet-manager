#!/usr/bin/env bash
# scripts/dependency-audit.sh - Dagelijkse dependency security audit
# Scant project dependencies op bekende kwetsbaarheden
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Dependency Security Audit ==="

# Configuratie
AUDIT_REPOS="${AUDIT_REPOS:-${KEY_REPOS[@]}}"
AUDIT_DRY_RUN="${AUDIT_DRY_RUN:-no}"

# Functies
audit_python_deps() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "  Auditing Python dependencies for $repo..."
  
  # Check of pip-audit beschikbaar is
  if ! command -v pip-audit &>/dev/null; then
    log "    ⚠️ pip-audit niet beschikbaar - skipping Python audit"
    return 0
  fi
  
  # Clone of gebruik bestaande checkout
  local tmpdir
  tmpdir=$(mktemp -d)
  git clone --depth 1 "https://github.com/${repo}.git" "$tmpdir/repo" 2>/dev/null || {
    log "    ⚠️ Kon repo niet clonen - skipping"
    rm -rf "$tmpdir"
    return 0
  }
  
  cd "$tmpdir/repo"
  
  # Zoek naar requirements.txt of pyproject.toml
  if [ -f "requirements.txt" ]; then
    log "    Gevonden: requirements.txt"
    pip-audit -r requirements.txt --format=json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    vulns = data.get('dependencies', [])
    for dep in vulns:
        for vuln in dep.get('vulns', []):
            print(f\"    ⚠️ {dep['name']} {dep['version']}: {vuln.get('id', 'unknown')} - {vuln.get('description', 'unknown')[:100]}\")
except:
    pass
" 2>/dev/null || log "    Geen kwetsbaarheden gevonden"
  elif [ -f "pyproject.toml" ]; then
    log "    Gevonden: pyproject.toml"
    pip-audit --format=json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    vulns = data.get('dependencies', [])
    for dep in vulns:
        for vuln in dep.get('vulns', []):
            print(f\"    ⚠️ {dep['name']} {dep['version']}: {vuln.get('id', 'unknown')} - {vuln.get('description', 'unknown')[:100]}\")
except:
    pass
" 2>/dev/null || log "    Geen kwetsbaarheden gevonden"
  else
    log "    Geen Python dependency bestanden gevonden"
  fi
  
  cd - >/dev/null
  rm -rf "$tmpdir"
}

audit_node_deps() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "  Auditing Node.js dependencies for $repo..."
  
  # Check of npm beschikbaar is
  if ! command -v npm &>/dev/null; then
    log "    ⚠️ npm niet beschikbaar - skipping Node.js audit"
    return 0
  fi
  
  # Clone of gebruik bestaande checkout
  local tmpdir
  tmpdir=$(mktemp -d)
  git clone --depth 1 "https://github.com/${repo}.git" "$tmpdir/repo" 2>/dev/null || {
    log "    ⚠️ Kon repo niet clonen - skipping"
    rm -rf "$tmpdir"
    return 0
  }
  
  cd "$tmpdir/repo"
  
  # Zoek naar package.json
  if [ -f "package.json" ]; then
    log "    Gevonden: package.json"
    npm audit --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    vulns = data.get('vulnerabilities', {})
    for name, info in vulns.items():
        severity = info.get('severity', 'unknown')
        if severity in ['high', 'critical']:
            print(f\"    ⚠️ {name}: {severity} - {info.get('title', 'unknown')[:100]}\")
except:
    pass
" 2>/dev/null || log "    Geen kwetsbaarheden gevonden"
  else
    log "    Geen package.json gevonden"
  fi
  
  cd - >/dev/null
  rm -rf "$tmpdir"
}

# Hoofdlogica
for repo in "${AUDIT_REPOS[@]}"; do
  log "Auditing $repo..."
  audit_python_deps "$repo"
  audit_node_deps "$repo"
done

log "=== Dependency Security Audit klaar ==="
