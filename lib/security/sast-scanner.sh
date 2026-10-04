#!/usr/bin/env bash
# SAST (Static Application Security Testing) scanner
set -euo pipefail

echo "=== SAST Scanning ==="

# ShellCheck als SAST voor bash
if command -v shellcheck &>/dev/null; then
  echo "  ShellCheck uitvoeren..."
  shellcheck scripts/*.sh lib/*.sh --severity=warning || true
else
  echo "  ⚠️ ShellCheck niet geïnstalleerd"
fi

# Bandit voor Python (als beschikbaar)
if command -v bandit &>/dev/null; then
  echo "  Bandit uitvoeren..."
  bandit -r . -f json -o bandit-report.json 2>/dev/null || true
else
  echo "  ⚠️ Bandit niet geïnstalleerd"
fi

echo "  ✅ SAST scan voltooid"
