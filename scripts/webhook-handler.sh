#!/usr/bin/env bash
# scripts/webhook-handler.sh - Webhook event handler
# Verwerkt GitHub webhook events voor auto-review, auto-triage, CI failure alerts
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Webhook Handler ==="

# Configuratie
WEBHOOK_EVENTS="${WEBHOOK_EVENTS:-pull_request,issues,check_run}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-}"

# Functies
handle_pull_request() {
  local action="$1"
  local pr_number="$2"
  local repo="$3"
  local title="$4"
  local author="$5"
  
  log "PR event: $action #$pr_number in $repo - $title by $author"
  
  case "$action" in
    opened|reopened)
      log "  → Trigger auto-review"
      bash "$(dirname "$0")/pr-review-agent.sh" --repo "$repo" --pr "$pr_number" 2>/dev/null || true
      ;;
    closed)
      log "  → PR closed, geen actie nodig"
      ;;
    *)
      log "  → Onbekende PR actie: $action"
      ;;
  esac
}

handle_issues() {
  local action="$1"
  local issue_number="$2"
  local repo="$3"
  local title="$4"
  local author="$5"
  
  log "Issue event: $action #$issue_number in $repo - $title by $author"
  
  case "$action" in
    opened|reopened)
      log "  → Trigger auto-triage"
      bash "$(dirname "$0")/nightly-backlog-triage.sh" --repo "$repo" --issue "$issue_number" 2>/dev/null || true
      ;;
    closed)
      log "  → Issue closed, geen actie nodig"
      ;;
    *)
      log "  → Onbekende issue actie: $action"
      ;;
  esac
}

handle_check_run() {
  local action="$1"
  local run_id="$2"
  local repo="$3"
  local status="$4"
  local conclusion="$5"
  
  log "Check run event: $action $run_id in $repo - status=$status conclusion=$conclusion"
  
  if [ "$conclusion" = "failure" ]; then
    log "  → Trigger CI failure summary"
    bash "$(dirname "$0")/ci-failure-summaries.sh" --repo "$repo" --run "$run_id" 2>/dev/null || true
  fi
}

# Hoofdlogica
if [ -z "$WEBHOOK_PAYLOAD" ]; then
  log "Geen webhook payload ontvangen - skipping"
  exit 0
fi

# Parse JSON payload
action=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('action',''))" 2>/dev/null || echo "")
event_type=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('event_type',''))" 2>/dev/null || echo "")

case "$event_type" in
  pull_request)
    pr_number=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pull_request',{}).get('number',''))" 2>/dev/null || echo "")
    repo=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('repository',{}).get('full_name',''))" 2>/dev/null || echo "")
    title=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pull_request',{}).get('title',''))" 2>/dev/null || echo "")
    author=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pull_request',{}).get('user',{}).get('login',''))" 2>/dev/null || echo "")
    handle_pull_request "$action" "$pr_number" "$repo" "$title" "$author"
    ;;
  issues)
    issue_number=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('issue',{}).get('number',''))" 2>/dev/null || echo "")
    repo=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('repository',{}).get('full_name',''))" 2>/dev/null || echo "")
    title=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('issue',{}).get('title',''))" 2>/dev/null || echo "")
    author=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('issue',{}).get('user',{}).get('login',''))" 2>/dev/null || echo "")
    handle_issues "$action" "$issue_number" "$repo" "$title" "$author"
    ;;
  check_run)
    run_id=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('check_run',{}).get('id',''))" 2>/dev/null || echo "")
    repo=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('repository',{}).get('full_name',''))" 2>/dev/null || echo "")
    status=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('check_run',{}).get('status',''))" 2>/dev/null || echo "")
    conclusion=$(echo "$WEBHOOK_PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('check_run',{}).get('conclusion',''))" 2>/dev/null || echo "")
    handle_check_run "$action" "$run_id" "$repo" "$status" "$conclusion"
    ;;
  *)
    log "Onbekend event type: $event_type"
    ;;
esac

log "=== Webhook Handler klaar ==="
