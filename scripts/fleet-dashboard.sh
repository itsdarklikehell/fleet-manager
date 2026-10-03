#!/usr/bin/env bash
# scripts/fleet-dashboard.sh - Fleet dashboard
# Genereert een HTML dashboard met real-time status van alle scripts, cron jobs en metrics
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Fleet Dashboard ==="

# Configuratie
DASHBOARD_DIR="${DASHBOARD_DIR:-$HOME/.github_fleet_dashboard}"
mkdir -p "$DASHBOARD_DIR"
DASHBOARD_FILE="$DASHBOARD_DIR/index.html"

# Functies
generate_dashboard() {
  local total_scripts
  total_scripts=$(ls scripts/*.sh 2>/dev/null | wc -l)
  local total_cron
  total_cron=$(crontab -l 2>/dev/null | grep -c 'github_fleet_wrapper' || echo "0")
  local active_scripts
  active_scripts=$(crontab -l 2>/dev/null | grep -oP 'github_fleet_wrapper\.sh \K[^ ]+' | sort -u | wc -l)
  
  # Rate limit
  local rate_remaining
  rate_remaining=$(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo "unknown")
  local rate_limit
  rate_limit=$(gh api rate_limit --jq '.resources.core.limit' 2>/dev/null || echo "unknown")
  
  # Laatste metrics
  local metrics_file
  metrics_file=$(ls -t ~/.github_fleet_metrics/metrics_*.json 2>/dev/null | head -1 || echo "")
  local total_repos="unknown"
  local total_issues="unknown"
  local total_prs="unknown"
  local total_ci_failures="unknown"
  
  if [ -n "$metrics_file" ] && [ -f "$metrics_file" ]; then
    total_repos=$(jq '.repos | length' "$metrics_file" 2>/dev/null || echo "unknown")
    total_issues=$(jq '[.repos[].open_issues] | add // 0' "$metrics_file" 2>/dev/null || echo "unknown")
    total_prs=$(jq '[.repos[].open_prs] | add // 0' "$metrics_file" 2>/dev/null || echo "unknown")
    total_ci_failures=$(jq '[.repos[].ci_failures_7d] | add // 0' "$metrics_file" 2>/dev/null || echo "unknown")
  fi
  
  # Laatste log entries
  local recent_logs
  recent_logs=$(tail -20 ~/.github_fleet_manager.log 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' || echo "Geen logs")
  
  # Cron jobs tabel
  local cron_table=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^# ]] && continue
    local schedule
    schedule=$(echo "$line" | awk '{print $1, $2, $3, $4, $5}')
    local script
    script=$(echo "$line" | sed -n 's/.*github_fleet_wrapper\.sh \([^ ]*\).*/\1/p')
    cron_table+="<tr><td>$schedule</td><td>$script</td></tr>"
  done < <(crontab -l 2>/dev/null | grep 'github_fleet_wrapper')
  
  # Genereer HTML
  cat > "$DASHBOARD_FILE" <<HTML
<!DOCTYPE html>
<html lang="nl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Fleet Dashboard</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0d1117; color: #c9d1d9; padding: 20px; }
    .container { max-width: 1200px; margin: 0 auto; }
    h1 { color: #58a6ff; margin-bottom: 20px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 15px; margin-bottom: 30px; }
    .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px; }
    .card h3 { color: #8b949e; font-size: 14px; margin-bottom: 10px; }
    .card .value { font-size: 32px; font-weight: bold; color: #58a6ff; }
    .card .sub { font-size: 12px; color: #8b949e; margin-top: 5px; }
    .section { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px; margin-bottom: 20px; }
    .section h2 { color: #58a6ff; margin-bottom: 15px; font-size: 18px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { text-align: left; padding: 8px 12px; border-bottom: 1px solid #30363d; }
    th { color: #8b949e; font-weight: 600; }
    .log { background: #0d1117; border: 1px solid #30363d; border-radius: 4px; padding: 10px; font-family: monospace; font-size: 12px; max-height: 300px; overflow-y: auto; }
    .log div { padding: 2px 0; }
    .status-ok { color: #3fb950; }
    .status-warn { color: #d29922; }
    .status-error { color: #f85149; }
    .refresh { color: #8b949e; font-size: 12px; margin-top: 10px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>🚢 Fleet Dashboard</h1>
    <p class="refresh">Laatste update: $(date '+%Y-%m-%d %H:%M:%S')</p>
    
    <div class="grid">
      <div class="card">
        <h3>Scripts</h3>
        <div class="value">$total_scripts</div>
        <div class="sub">Totaal modulaire scripts</div>
      </div>
      <div class="card">
        <h3>Cron Jobs</h3>
        <div class="value">$total_cron</div>
        <div class="sub">$active_scripts actieve scripts</div>
      </div>
      <div class="card">
        <h3>Repos</h3>
        <div class="value">$total_repos</div>
        <div class="sub">Beheerde repositories</div>
      </div>
      <div class="card">
        <h3>Open Issues</h3>
        <div class="value">$total_issues</div>
        <div class="sub">Totaal open issues</div>
      </div>
      <div class="card">
        <h3>Open PRs</h3>
        <div class="value">$total_prs</div>
        <div class="sub">Totaal open PRs</div>
      </div>
      <div class="card">
        <h3>CI Failures</h3>
        <div class="value">$total_ci_failures</div>
        <div class="sub">Laatste 7 dagen</div>
      </div>
      <div class="card">
        <h3>API Rate Limit</h3>
        <div class="value">$rate_remaining</div>
        <div class="sub">van $rate_limit remaining</div>
      </div>
    </div>
    
    <div class="section">
      <h2>📋 Cron Jobs</h2>
      <table>
        <thead>
          <tr><th>Schedule</th><th>Script</th></tr>
        </thead>
        <tbody>
          $cron_table
        </tbody>
      </table>
    </div>
    
    <div class="section">
      <h2>📜 Recente Logs</h2>
      <div class="log">
        $(echo "$recent_logs" | sed 's/$/<br>/')
      </div>
    </div>
  </div>
</body>
</html>
HTML
  
  echo "  ✅ Dashboard gegenereerd: $DASHBOARD_FILE"
}

# Hoofdlogica
generate_dashboard

echo ""
echo "✅ Fleet dashboard klaar"
echo "  Open: $DASHBOARD_FILE"
