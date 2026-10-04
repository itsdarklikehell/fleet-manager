#!/usr/bin/env bash
# Integration tests voor fleet-manager
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"

echo "=== Integration Tests ==="

test_git_repo() {
  if git rev-parse --git-dir > /dev/null 2>&1; then
    echo "  ✅ Git repo: OK"
    return 0
  else
    echo "  ❌ Git repo: fout"
    return 1
  fi
}

test_gh_cli() {
  if command -v gh &>/dev/null; then
    echo "  ✅ gh CLI: beschikbaar"
    return 0
  else
    echo "  ❌ gh CLI: niet beschikbaar"
    return 1
  fi
}

test_telegram() {
  if [ -n "${TELEGRAM_TOKEN:-}" ]; then
    echo "  ✅ Telegram token: gezet"
    return 0
  else
    echo "  ⚠️ Telegram token: niet gezet (optioneel)"
    return 0
  fi
}

test_cron() {
  if crontab -l > /dev/null 2>&1; then
    echo "  ✅ Crontab: OK"
    return 0
  else
    echo "  ❌ Crontab: fout"
    return 1
  fi
}

# Voer tests uit
test_git_repo
test_gh_cli
test_telegram
test_cron

echo ""
echo "  ✅ Integration tests voltooid"
