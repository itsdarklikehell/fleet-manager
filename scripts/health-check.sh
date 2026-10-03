#!/usr/bin/env bash
# scripts/health-check.sh - Health check voor alle fleet-manager scripts
# Verifieert dat alle scripts correct zijn geïnstalleerd en werken
# Uitgebreid met: laatste run tracking, rate limit monitoring, falen detectie
set -euo pipefail

# Laad environment
source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Fleet Manager Health Check ==="

# Configuratie
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-10}"
HEALTH_STATE_DIR="${HEALTH_STATE_DIR:-$HOME/.github_fleet_health}"
mkdir -p "$HEALTH_STATE_DIR"

# Functies
check_script() {
  local script="$1"
  local path="scripts/$script"
  
  if [ ! -f "$path" ]; then
    log "  ❌ $script: niet gevonden"
    return 1
  fi
  
  if [ ! -x "$path" ]; then
    log "  ⚠️ $script: niet executebaar"
  fi
  
  if ! bash -n "$path" 2>/dev/null; then
    log "  ❌ $script: syntax error"
    return 1
  fi
  
  log "  ✅ $script: OK"
  return 0
}

check_dependency() {
  local cmd="$1"
  local package="${2:-$1}"
  
  if command -v "$cmd" &>/dev/null; then
    log "  ✅ $cmd: beschikbaar"
    return 0
  else
    log "  ⚠️ $cmd: niet beschikbaar (installeer: $package)"
    return 1
  fi
}

check_env_var() {
  local var="$1"
  local required="${2:-no}"
  
  if [ -n "${!var:-}" ]; then
    log "  ✅ $var: gezet"
    return 0
  elif [ "$required" = "yes" ]; then
    log "  ❌ $var: vereist maar niet gezet"
    return 1
  else
    log "  ⚠️ $var: niet gezet (optioneel)"
    return 0
  fi
}

check_cron_job() {
  local job_name="$1"
  
  if crontab -l 2>/dev/null | grep -q "$job_name"; then
    log "  ✅ Cron job '$job_name': actief"
    return 0
  else
    log "  ⚠️ Cron job '$job_name': niet gevonden"
    return 1
  fi
}

# Nieuw: laatste run timestamp bijhouden
record_run() {
  local script="$1"
  local status="$2"
  local state_file="$HEALTH_STATE_DIR/${script}.last_run"
  echo "$(date +%s) $status" > "$state_file"
}

# Nieuw: detecteer scripts die te lang niet hebben gedraaid
check_stale_scripts() {
  local max_age="${STALE_SCRIPT_AGE:-86400}"  # 24 uur
  local now
  now=$(date +%s)
  local stale=0
  
  for state_file in "$HEALTH_STATE_DIR"/*.last_run; do
    [ -f "$state_file" ] || continue
    local script
    script=$(basename "$state_file" .last_run)
    local last_run
    last_run=$(cat "$state_file" 2>/dev/null | cut -d' ' -f1 || echo "0")
    local age=$((now - last_run))
    if [ "$age" -gt "$max_age" ]; then
      log "  ⚠️ $script: ${age}s sinds laatste run (max ${max_age}s)"
      stale=$((stale + 1))
    fi
  done
  
  if [ "$stale" -gt 0 ]; then
    log "  ⚠️ $stale script(s) zijn stale"
  fi
  return 0
}

# Nieuw: detecteer opeenvolgende falen
check_consecutive_failures() {
  local max_failures="${MAX_CONSECUTIVE_FAILURES:-3}"
  local state_file="$HEALTH_STATE_DIR/consecutive_failures"
  local failures=0
  
  if [ -f "$state_file" ]; then
    failures=$(cat "$state_file" 2>/dev/null || echo "0")
  fi
  
  if [ "$failures" -ge "$max_failures" ]; then
    log "  ❌ $failures opeenvolgende falen gedetecteerd!"
    # Reset na rapportage
    echo "0" > "$state_file"
    return 1
  fi
  return 0
}

# Nieuw: rate limit monitoring
check_rate_limit() {
  local remaining
  remaining=$(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo "unknown")
  if [ "$remaining" != "unknown" ]; then
    if [ "$remaining" -lt 100 ]; then
      log "  ❌ GitHub API rate limit kritiek: $remaining remaining"
      return 1
    elif [ "$remaining" -lt 500 ]; then
      log "  ⚠️ GitHub API rate limit laag: $remaining remaining"
    else
      log "  ✅ GitHub API rate limit: $remaining remaining"
    fi
  fi
  return 0
}

# Hoofdlogica
log "Checking scripts..."
scripts=(
  "inbox-reader.sh"
  "pr-review-agent.sh"
  "ci-failure-summaries.sh"
  "nightly-backlog-triage.sh"
  "docs-drift-detection.sh"
  "dependency-audit.sh"
  "delivery-router.sh"
  "mcp-github-bridge.sh"
  "fleet-automation-suite.sh"
  "multi-tool-chaining.sh"
  "model-router.sh"
  "a2a-bridge.sh"
  "webhook-handler.sh"
  "autonomous-pr-workflow.sh"
  "release-automation.sh"
  "changelog-generator.sh"
  "secret-scanning.sh"
  "license-compliance-check.sh"
  "repo-health-score.sh"
  "security-advisory-monitor.sh"
  "code-quality-metrics.sh"
  "automated-dependency-updates.sh"
  "branch-protection-enforcement.sh"
  "repo-archiving-suggestions.sh"
  "mcp-inbox-reader.sh"
  "auto-issue-responder.sh"
  "auto-labeling.sh"
  "auto-merge.sh"
  "stale-issue-detection.sh"
  "release-publishing.sh"
  "documentation-generation.sh"
  "dependency-security-fixes.sh"
  "test-execution-reporting.sh"
  "multi-repo-coordination.sh"
  "profile-data-generator.sh"
  "run-all-dry-runs.sh"
)

script_ok=0
script_fail=0
for script in "${scripts[@]}"; do
  if check_script "$script"; then
    script_ok=$((script_ok + 1))
    record_run "$script" "ok"
  else
    script_fail=$((script_fail + 1))
    record_run "$script" "fail"
  fi
done

log ""
log "Checking dependencies..."
check_dependency "gh" "GitHub CLI"
check_dependency "curl" "curl"
check_dependency "python3" "Python 3"
check_dependency "jq" "jq"
check_dependency "git" "Git"

log ""
log "Checking environment variables..."
# Accepteer zowel GITHUB_TOKEN als GH_TOKEN (wordt gezet door .env)
if [ -n "${GITHUB_TOKEN:-}" ] || [ -n "${GH_TOKEN:-}" ]; then
  log "  ✅ GITHUB_TOKEN/GH_TOKEN: gezet"
else
  log "  ❌ GITHUB_TOKEN/GH_TOKEN: vereist maar niet gezet"
  return 1
fi
check_env_var "TELEGRAM_TOKEN" "no"
check_env_var "TELEGRAM_CHAT_ID" "no"

log ""
log "Checking cron jobs..."
check_cron_job "inbox-reader"
check_cron_job "pr-review-agent"
check_cron_job "ci-failure-summaries"
check_cron_job "nightly-backlog-triage"
check_cron_job "docs-drift-detection"
check_cron_job "dependency-audit"
check_cron_job "delivery-router"
check_cron_job "mcp-github-bridge"
check_cron_job "fleet-automation-suite"

log ""
log "Checking rate limit..."
check_rate_limit

log ""
log "Checking stale scripts..."
check_stale_scripts

log ""
log "Checking consecutive failures..."
check_consecutive_failures

log ""
log "=== Health Check Samenvatting ==="
log "Scripts: $script_ok OK, $script_fail failed"
log "=== Health Check klaar ==="
