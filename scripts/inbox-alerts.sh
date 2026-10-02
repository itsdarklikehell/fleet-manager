#!/usr/bin/env bash
# scripts/inbox-alerts.sh - Alerts voor belangrijke items
# Waarschuwt voor belangrijke issues, PRs en security items
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Alerts ==="

# shellcheck disable=SC2206
ALERT_REPOS=( ${ALERT_REPOS:-${KEY_REPOS[@]}} )
TODAY=$(date '+%Y-%m-%d')

# Fase 1: Security issues
log "Fase 1: Security issues..."
security_issues=""
for kr in "${ALERT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  sec_issues=$(gh issue list --repo "$kr" --state open --label "security" --limit 50 --json title,url,createdAt --jq '.[] | "• [\(.title)](\(.url)) — \(.createdAt[:10])"' 2>/dev/null || echo "")
  if [ -n "$sec_issues" ]; then
    security_issues="$security_issues
$sec_issues"
    log "  $kr: security issues gevonden"
  fi
done

# Fase 2: Bug issues met hoge prioriteit
log "Fase 2: Bug issues..."
bug_issues=""
for kr in "${ALERT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  bugs=$(gh issue list --repo "$kr" --state open --label "bug" --limit 50 --json title,url,createdAt --jq '.[] | "• [\(.title)](\(.url)) — \(.createdAt[:10])"' 2>/dev/null || echo "")
  if [ -n "$bugs" ]; then
    bug_issues="$bug_issues
$bugs"
    log "  $kr: bug issues gevonden"
  fi
done

# Fase 3: PRs die lang open staan
log "Fase 3: Lange PRs..."
stale_prs=""
for kr in "${ALERT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  stale=$(gh pr list --repo "$kr" --state open --limit 50 --json title,url,createdAt --jq "[.[] | select(.createdAt < \"$(date -d '14 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-14d '+%Y-%m-%d' 2>/dev/null || echo '2025-01-01')T00:00:00Z\")] | .[] | \"• [\(.title)](\(.url)) — \(.createdAt[:10])\"" 2>/dev/null || echo "")
  if [ -n "$stale" ]; then
    stale_prs="$stale_prs
$stale"
    log "  $kr: stale PRs gevonden"
  fi
done

# Fase 4: Failing CI
log "Fase 4: Failing CI..."
failing_ci=""
for kr in "${ALERT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  failing=$(gh run list --repo "$kr" --limit 20 --json name,conclusion,url,createdAt --jq '[.[] | select(.conclusion == "failure")] | .[] | "• \(.name) — \(.createdAt[:10]) — \(.url)"' 2>/dev/null || echo "")
  if [ -n "$failing" ]; then
    failing_ci="$failing_ci
$failing"
    log "  $kr: failing CI gevonden"
  fi
done

# Fase 5: Verstuur alerts
log "Fase 5: Verstuur alerts..."

alert_message="🚨 *Inbox Alerts* — $TODAY"

if [ -n "$security_issues" ]; then
  alert_message="$alert_message

🔒 *Security Issues:*
$security_issues"
fi

if [ -n "$bug_issues" ]; then
  alert_message="$alert_message

🐛 *Bug Issues:*
$bug_issues"
fi

if [ -n "$stale_prs" ]; then
  alert_message="$alert_message

⏰ *Stale PRs (>14d):*
$stale_prs"
fi

if [ -n "$failing_ci" ]; then
  alert_message="$alert_message

🔴 *Failing CI:*
$failing_ci"
fi

if [ "$alert_message" = "🚨 *Inbox Alerts* — $TODAY" ]; then
  alert_message="$alert_message

✅ Geen alerts — alles is oranje!"
fi

send_telegram_message "$alert_message" || true

log "=== Inbox Alerts complete ==="
