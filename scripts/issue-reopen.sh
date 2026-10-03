#!/usr/bin/env bash
# scripts/issue-reopen.sh - Reopen issues
set -euo pipefail

# DRY_RUN guard
DRY_RUN="${GITHUB_FLEET_DRY_RUN:-}"
maybe_mutate() {
  if [ -n "$DRY_RUN" ]; then
    log "🔒 [DRY-RUN] Would: $*"
    return 0
  fi
  "$@"
}
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --issue <number> [--comment <comment>]

Reopen a closed issue.

Options:
  --repo <org/repo>       Repository (required)
  --issue <number>        Issue number (required)
  --comment <comment>     Comment to add when reopening
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --issue 42
  $0 --repo itsdarklikehell/hermes-agent --issue 10 --comment "Reopening — still relevant"
EOF
}

REPO=""
ISSUE=""
COMMENT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --issue) ISSUE="$2"; shift 2 ;;
    --comment) COMMENT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$ISSUE" ] && { echo "Error: --issue is required" >&2; usage; exit 1; }

log "=== Issue Reopen: $REPO#$ISSUE ==="

# Add comment first if provided
if [ -n "$COMMENT" ]; then
  if maybe_mutate gh issue comment "$ISSUE" --repo "$REPO" --body "$COMMENT"; then
    log "  ✓ Comment toegevoegd aan #$ISSUE"
  else
    log "  ✗ Comment toevoegen failed voor #$ISSUE"
  fi
fi

# Reopen the issue
if maybe_mutate gh issue reopen "$ISSUE" --repo "$REPO"; then
  log "  ✓ Issue #$ISSUE heropend in $REPO"
  send_telegram_message "🔓 *Issue Reopened*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE" || true
else
  log "  ✗ Issue reopen failed voor $REPO#$ISSUE"
  send_telegram_message "❌ *Issue Reopen Failed*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE" || true
  exit 1
fi
