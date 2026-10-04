#!/usr/bin/env bash
# scripts/setup-webhook-server.sh - Webhook server implementeren
# Real-time reacties op GitHub events (PR, issues, push)
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup Webhook Server ==="

# Configuratie
WEBHOOK_DIR="lib/webhook"
mkdir -p "$WEBHOOK_DIR"

# Functies
create_webhook_server() {
  local server="$WEBHOOK_DIR/server.py"
  
  cat > "$server" << 'PYTHON'
#!/usr/bin/env python3
"""GitHub webhook server voor fleet-manager."""
import http.server
import json
import hmac
import hashlib
import os
import subprocess
import sys

PORT = int(os.environ.get('WEBHOOK_PORT', '9121'))
SECRET = os.environ.get('WEBHOOK_SECRET', '')
LOG_FILE = os.environ.get('WEBHOOK_LOG', os.path.expanduser('~/.github_fleet_webhook.log'))

def log_event(event_type, payload):
    """Log webhook event."""
    with open(LOG_FILE, 'a') as f:
        f.write(f"[{event_type}] {json.dumps(payload)[:200]}\n")

def handle_pull_request(payload):
    """Handle pull_request events."""
    action = payload.get('action', '')
    pr_number = payload.get('pull_request', {}).get('number', '')
    repo = payload.get('repository', {}).get('full_name', '')
    log_event('pull_request', {'action': action, 'pr': pr_number, 'repo': repo})
    
    if action == 'opened':
        subprocess.Popen(['bash', 'scripts/ai-pr-review.sh', repo, str(pr_number)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def handle_issues(payload):
    """Handle issues events."""
    action = payload.get('action', '')
    issue_number = payload.get('issue', {}).get('number', '')
    repo = payload.get('repository', {}).get('full_name', '')
    log_event('issues', {'action': action, 'issue': issue_number, 'repo': repo})
    
    if action == 'opened':
        subprocess.Popen(['bash', 'scripts/ai-issue-triage.sh', repo, str(issue_number)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def handle_push(payload):
    """Handle push events."""
    ref = payload.get('ref', '')
    repo = payload.get('repository', {}).get('full_name', '')
    log_event('push', {'ref': ref, 'repo': repo})

class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        if SECRET:
            signature = self.headers.get('X-Hub-Signature-256', '')
            expected = 'sha256=' + hmac.new(SECRET.encode(), body, hashlib.sha256).hexdigest()
            if not hmac.compare_digest(signature, expected):
                self.send_response(401)
                self.end_headers()
                return
        
        event_type = self.headers.get('X-GitHub-Event', '')
        payload = json.loads(body)
        
        if event_type == 'pull_request':
            handle_pull_request(payload)
        elif event_type == 'issues':
            handle_issues(payload)
        elif event_type == 'push':
            handle_push(payload)
        
        self.send_response(200)
        self.end_headers()

if __name__ == '__main__':
    server = http.server.HTTPServer(('0.0.0.0', PORT), WebhookHandler)
    print(f"Webhook server actief op poort {PORT}")
    server.serve_forever()
PYTHON
  
  chmod +x "$server"
  echo "  ✅ Webhook server gemaakt"
}

create_webhook_service() {
  local service_file="$HOME/.config/systemd/user/fleet-webhook.service"
  mkdir -p "$(dirname "$service_file")"
  
  cat > "$service_file" << SERVICE
[Unit]
Description=Fleet Webhook Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $(pwd)/lib/webhook/server.py
Restart=on-failure
RestartSec=5
Environment=WEBHOOK_PORT=9121

[Install]
WantedBy=default.target
SERVICE
  
  echo "  ✅ Webhook service gemaakt"
}

# Hoofdlogica
create_webhook_server
create_webhook_service

echo ""
echo "✅ Webhook server setup klaar"
