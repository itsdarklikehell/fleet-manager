#!/usr/bin/env bash
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Monitoring Dashboard ==="

# Service status
for service in fleet-dashboard fleet-webhook fleet-grafana fleet-prometheus fleet-vault; do
    status=$(systemctl --user is-active ${service}.service 2>/dev/null || echo 'inactive')
    echo "  $service: $status"
done

# Cron jobs
jobs=$(crontab -l 2>/dev/null | grep -c 'github_fleet_wrapper' || echo 0)
echo "  Cron jobs: $jobs"

# Scripts
scripts=$(ls scripts/*.sh 2>/dev/null | wc -l)
echo "  Scripts: $scripts"

# Git status
git_status=$(git status --short 2>/dev/null | wc -l)
echo "  Git: $git_status bestanden gewijzigd"
