#!/usr/bin/env bash
# scripts/fleet-automation-suite.sh - Master automation suite
# Voert alle fleet-manager automation scripts uit in de juiste volgorde
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Fleet Automation Suite ==="

# Configuratie
SUITE_DRY_RUN="${SUITE_DRY_RUN:-no}"
SUITE_SKIP_AUDIT="${SUITE_SKIP_AUDIT:-no}"
SUITE_SKIP_TRIAGE="${SUITE_SKIP_TRIAGE:-no}"
SUITE_SKIP_REVIEW="${SUITE_SKIP_REVIEW:-no}"
SUITE_SKIP_DELIVERY="${SUITE_SKIP_DELIVERY:-no}"

# Functies
run_script() {
  local script="$1"
  local description="$2"
  local args="${3:-}"
  
  log "Running: $description"
  
  if [ "$SUITE_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would run: bash scripts/$script $args"
    return 0
  fi
  
  if bash "scripts/$script" $args 2>&1; then
    log "  ✅ $description completed"
  else
    log "  ❌ $description failed"
    return 1
  fi
}

# Fase 1: Inbox & Triage
if [ "$SUITE_SKIP_TRIAGE" != "yes" ]; then
  run_script "inbox-reader.sh" "Inbox Reader"
  run_script "mcp-inbox-reader.sh" "MCP Inbox Reader"
  run_script "nightly-backlog-triage.sh" "Nightly Backlog Triage"
fi

# Fase 2: PR Review
if [ "$SUITE_SKIP_REVIEW" != "yes" ]; then
  run_script "pr-review-agent.sh" "PR Review Agent"
  run_script "ci-failure-summaries.sh" "CI Failure Summaries"
fi

# Fase 3: Audits
if [ "$SUITE_SKIP_AUDIT" != "yes" ]; then
  run_script "docs-drift-detection.sh" "Docs Drift Detection"
  run_script "dependency-audit.sh" "Dependency Audit"
fi

# Fase 4: Delivery
if [ "$SUITE_SKIP_DELIVERY" != "yes" ]; then
  run_script "delivery-router.sh" "Delivery Router"
fi

# Fase 5: MCP Bridge
run_script "mcp-github-bridge.sh" "GitHub MCP Bridge"

# Fase 6: Model Router
run_script "model-router.sh" "Model Router"

# Fase 7: A2A Bridge
run_script "a2a-bridge.sh" "A2A Bridge"

# Fase 8: Webhook Handler
run_script "webhook-handler.sh" "Webhook Handler"

# Fase 9: Release Automation
run_script "release-automation.sh" "Release Automation"

# Fase 10: Changelog Generator
run_script "changelog-generator.sh" "Changelog Generator"

# Fase 11: Secret Scanning
run_script "secret-scanning.sh" "Secret Scanning"

# Fase 12: License Compliance
run_script "license-compliance-check.sh" "License Compliance Check"

# Fase 13: Repo Health Score
run_script "repo-health-score.sh" "Repo Health Score"

# Fase 14: Security Advisory Monitor
run_script "security-advisory-monitor.sh" "Security Advisory Monitor"

# Fase 15: Code Quality Metrics
run_script "code-quality-metrics.sh" "Code Quality Metrics"

# Fase 16: Automated Dependency Updates
run_script "automated-dependency-updates.sh" "Automated Dependency Updates"

# Fase 17: Branch Protection Enforcement
run_script "branch-protection-enforcement.sh" "Branch Protection Enforcement"

# Fase 18: Repo Archiving Suggestions
run_script "repo-archiving-suggestions.sh" "Repo Archiving Suggestions"

# Fase 19: Batch Dry-Run Test
run_script "run-all-dry-runs.sh" "Batch Dry-Run Test"

log "=== Fleet Automation Suite klaar ==="
