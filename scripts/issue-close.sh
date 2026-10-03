#!/usr/bin/env bash
# scripts/issue-close.sh - Close issues met comment
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
Usage: $0 --repo <org/repo> --issue <number> [--comment <comment>] [--reason <completed|not_planned>]

Close an issue with an optional comment.

Options:
  --repo <org/repo>       Repository (required)
  --issue <number>        Issue number (required)
  --comment <comment>     Comment to add before closing
  --reason <reason>       Close reason: completed (default) or not_planned
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --issue 42
  $0 --repo itsdarklikehell/hermes-agent --issue 10 --comment "Fixed in v2.0" --reason completed
EOF
}

REPO=""
ISSUE=""
COMMENT=""
REASON="completed"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --issue) ISSUE="$2"; shift 2 ;;
    --comment) COMMENT="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$ISSUE" ] && { echo "Error: --issue is required" >&2; usage; exit 1; }

log "=== Issue Close: $REPO#$ISSUE ==="

# Add comment first if provided
if [ -n "$COMMENT" ]; then
  if maybe_mutate gh issue comment "$ISSUE" --repo "$REPO" --body "$COMMENT"; then
    log "  ✓ Comment toegevoegd aan #$ISSUE"
  else
    log "  ✗ Comment toevoegen failed voor #$ISSUE"
  fi
fi

# Close the issue
if maybe_mutate gh issue close "$ISSUE" --repo "$REPO" --reason "$REASON"; then
  log "  ✓ Issue #$ISSUE gesloten in $REPO"
  send_telegram_message "🔒 *Issue Closed*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE\n*Reason:* $REASON" || true
else
  log "  ✗ Issue close failed voor $REPO#$ISSUE"
  send_telegram_message "❌ *Issue Close Failed*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE" || true
  exit 1
fi
