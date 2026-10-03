#!/usr/bin/env bash
# scripts/webhook-server.sh - Webhook server voor GitHub events
# Real-time reacties op PR, issue en push events
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Webhook Server ==="

# Configuratie
WEBHOOK_PORT="${WEBHOOK_PORT:-9121}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-}"
WEBHOOK_LOG="${WEBHOOK_LOG:-$HOME/.github_fleet_webhook.log}"

# Functies
handle_pull_request() {
  local payload="$1"
  local action
  action=$(echo "$payload" | jq -r '.action')
  local pr_number
  pr_number=$(echo "$payload" | jq -r '.pull_request.number')
  local repo
  repo=$(echo "$payload" | jq -r '.repository.full_name')
  
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] PR #$pr_number $action in $repo" >> "$WEBHOOK_LOG"
  
  case "$action" in
    opened)
      # Auto-review starten
      bash scripts/ai-pr-review.sh "$repo" "$pr_number" &
      ;;
    synchronize)
      # Nieuwe commits — review bijwerken
      bash scripts/ai-pr-review.sh "$repo" "$pr_number" &
      ;;
  esac
}

handle_issues() {
  local payload="$1"
  local action
  action=$(echo "$payload" | jq -r '.action')
  local issue_number
  issue_number=$(echo "$payload" | jq -r '.issue.number')
  local repo
  repo=$(echo "$payload" | jq -r '.repository.full_name')
  
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Issue #$issue_number $action in $repo" >> "$WEBHOOK_LOG"
  
  case "$action" in
    opened)
      # Auto-triage starten
      bash scripts/ai-issue-triage.sh "$repo" "$issue_number" &
      ;;
  esac
}

handle_push() {
  local payload="$1"
  local repo
  repo=$(echo "$payload" | jq -r '.repository.full_name')
  local ref
  ref=$(echo "$payload" | jq -r '.ref')
  
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Push naar $ref in $repo" >> "$WEBHOOK_LOG"
  
  # CI failure check
  bash scripts/ci-failure-check.sh &
}

# Start webhook server
echo "Webhook server starten op poort $WEBHOOK_PORT..."

# Gebruik python3 voor de webhook server
python3 << PYTHON &
import http.server
import json
import hmac
import hashlib
import os
import sys

PORT = int(os.environ.get('WEBHOOK_PORT', '9121'))
SECRET = os.environ.get('WEBHOOK_SECRET', '')
LOG_FILE = os.environ.get('WEBHOOK_LOG', os.path.expanduser('~/.github_fleet_webhook.log'))

class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        # Verifieer signature
        if SECRET:
            signature = self.headers.get('X-Hub-Signature-256', '')
            expected = 'sha256=' + hmac.new(SECRET.encode(), body, hashlib.sha256).hexdigest()
            if not hmac.compare_digest(signature, expected):
                self.send_response(401)
                self.end_headers()
                return
        
        # Parse event
        event_type = self.headers.get('X-GitHub-Event', '')
        payload = json.loads(body)
        
        # Log
        with open(LOG_FILE, 'a') as f:
            f.write(f"[{event_type}] {json.dumps(payload)[:200]}\n")
        
        # Route event
        if event_type == 'pull_request':
            self.handle_pull_request(payload)
        elif event_type == 'issues':
            self.handle_issues(payload)
        elif event_type == 'push':
            self.handle_push(payload)
        
        self.send_response(200)
        self.end_headers()
    
    def handle_pull_request(self, payload):
        action = payload.get('action', '')
        pr_number = payload.get('pull_request', {}).get('number', '')
        repo = payload.get('repository', {}).get('full_name', '')
        print(f"PR #{pr_number} {action} in {repo}")
    
    def handle_issues(self, payload):
        action = payload.get('action', '')
        issue_number = payload.get('issue', {}).get('number', '')
        repo = payload.get('repository', {}).get('full_name', '')
        print(f"Issue #{issue_number} {action} in {repo}")
    
    def handle_push(self, payload):
        ref = payload.get('ref', '')
        repo = payload.get('repository', {}).get('full_name', '')
        print(f"Push naar {ref} in {repo}")

server = http.server.HTTPServer(('0.0.0.0', PORT), WebhookHandler)
print(f"Webhook server actief op poort {PORT}")
server.serve_forever()
PYTHON

WEBHOOK_PID=$!
echo "  ✅ Webhook server gestart (PID: $WEBHOOK_PID)"
echo "  Poort: $WEBHOOK_PORT"
echo "  Log: $WEBHOOK_LOG"

# Sla PID op
echo "$WEBHOOK_PID" > "$HOME/.github_fleet_webhook.pid"

echo ""
echo "✅ Webhook server klaar"
