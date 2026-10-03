#!/usr/bin/env bash
# scripts/secret-scanning.sh - Secret scanning voor hardcoded credentials
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Secret Scanning ==="

# Configuratie
SS_ENABLED="${SS_ENABLED:-yes}"
SS_DRY_RUN="${SS_DRY_RUN:-yes}"
SS_REPO="${SS_REPO:-}"
SS_ORG="${SS_ORG:-itsdarklikehell}"

# Functies
scan_for_secrets() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Scanning $repo for hardcoded secrets..."
  
  local findings=""
  
  # Clone repo tijdelijk met retry
  local tmpdir
  tmpdir=$(mktemp -d)
  
  local clone_ok=false
  for attempt in 1 2 3; do
    if git clone --depth 1 "https://github.com/$repo.git" "$tmpdir/repo" 2>/dev/null; then
      clone_ok=true
      break
    fi
    log "  ⚠️ Clone poging $attempt gefaald, opnieuw proberen..."
    sleep 2
  done
  
  if [ "$clone_ok" != true ]; then
    log "  ❌ Kon repo niet clonen na 3 pogingen"
    rm -rf "$tmpdir"
    return 1
  fi
  
  cd "$tmpdir/repo"
  
  # Zoek naar hardcoded secrets
  # 1. API Keys
  local api_keys
  api_keys=$(grep -rE "(api[_-]?key|api[_-]?secret|api[_-]?token)\s*[:=]\s*['\"][^'\"]{20,}" --include="*.py" --include="*.js" --include="*.ts" --include="*.sh" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.env" . 2>/dev/null || echo "")
  
  if [ -n "$api_keys" ]; then
    findings+="## 🔑 API Keys\n\n"
    findings+=$(echo "$api_keys" | sed 's/^/- /')
    findings+="\n\n"
  fi
  
  # 2. Passwords
  local passwords
  passwords=$(grep -rE "(password|passwd|pwd)\s*[:=]\s*['\"][^'\"]{8,}" --include="*.py" --include="*.js" --include="*.ts" --include="*.sh" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.env" . 2>/dev/null || echo "")
  
  if [ -n "$passwords" ]; then
    findings+="## 🔒 Passwords\n\n"
    findings+=$(echo "$passwords" | sed 's/^/- /')
    findings+="\n\n"
  fi
  
  # 3. Tokens
  local tokens
  tokens=$(grep -rE "(token|secret|key)\s*[:=]\s*['\"][a-zA-Z0-9_\-]{20,}" --include="*.py" --include="*.js" --include="*.ts" --include="*.sh" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.env" . 2>/dev/null || echo "")
  
  if [ -n "$tokens" ]; then
    findings+="## 🎫 Tokens\n\n"
    findings+=$(echo "$tokens" | sed 's/^/- /')
    findings+="\n\n"
  fi
  
  # 4. Private keys
  local private_keys
  private_keys=$(grep -rE "BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY" --include="*.pem" --include="*.key" --include="*.p12" --include="*.pfx" . 2>/dev/null || echo "")
  
  if [ -n "$private_keys" ]; then
    findings+="## 🔐 Private Keys\n\n"
    findings+=$(echo "$private_keys" | sed 's/^/- /')
    findings+="\n\n"
  fi
  
  # 5. AWS keys
  local aws_keys
  aws_keys=$(grep -rE "AKIA[0-9A-Z]{16}" --include="*.py" --include="*.js" --include="*.ts" --include="*.sh" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.env" . 2>/dev/null || echo "")
  
  if [ -n "$aws_keys" ]; then
    findings+="## ☁️ AWS Keys\n\n"
    findings+=$(echo "$aws_keys" | sed 's/^/- /')
    findings+="\n\n"
  fi
  
  # 6. GitHub tokens
  local gh_tokens
  gh_tokens=$(grep -rE "ghp_[a-zA-Z0-9]{36}" --include="*.py" --include="*.js" --include="*.ts" --include="*.sh" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.env" . 2>/dev/null || echo "")
  
  if [ -n "$gh_tokens" ]; then
    findings+="## 🐙 GitHub Tokens\n\n"
    findings+=$(echo "$gh_tokens" | sed 's/^/- /')
    findings+="\n\n"
  fi
  
  cd - >/dev/null
  rm -rf "$tmpdir"
  
  if [ -n "$findings" ]; then
    echo -e "$findings"
    return 0
  else
    log "  ✅ Geen secrets gevonden"
    return 1
  fi
}

create_security_issue() {
  local repo="$1"
  local findings="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Creating security issue for $repo..."
  
  if [ "$SS_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would create security issue"
    return 0
  fi
  
  local body
  body=$(cat <<EOF
## 🔒 Secret Scan Results

De secret scan heeft mogelijk hardcoded credentials gevonden in deze repository:

$findings

### Aanbevelingen

1. Verwijder alle hardcoded secrets uit de code
2. Gebruik environment variables of een secret manager
3. Rotate alle gevonden credentials
4. Voeg `.env` en `*.key` toe aan `.gitignore`

---
*Deze issue is automatisch aangemaakt door de GitHub Fleet Manager.*
EOF
)
  
  gh issue create \
    --repo "$repo" \
    --title "🔒 Secret scan: mogelijk hardcoded credentials gevonden" \
    --body "$body" \
    --label "security" 2>/dev/null && log "  ✅ Security issue aangemaakt" || log "  ❌ Kon security issue niet aanmaken"
}

# Hoofdlogica
if [ "$SS_ENABLED" != "yes" ]; then
  log "Secret scanning uitgeschakeld"
  exit 0
fi

if [ -z "$SS_REPO" ]; then
  log "SS_REPO niet ingesteld - skipping"
  exit 0
fi

log "Starting secret scanning for $SS_REPO..."

# Scan voor secrets
findings=$(scan_for_secrets "$SS_REPO")

if [ -n "$findings" ]; then
  log "  ⚠️ Secrets gevonden!"
  create_security_issue "$SS_REPO" "$findings"
else
  log "  ✅ Geen secrets gevonden"
fi

log "=== Secret Scanning klaar ==="
