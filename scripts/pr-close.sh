#!/usr/bin/env bash
# scripts/pr-close.sh - Close PRs met comment
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
Usage: $0 --repo <org/repo> --pr <number> [--comment <comment>]

Close a pull request with an optional comment.

Options:
  --repo <org/repo>       Repository (required)
  --pr <number>           PR number (required)
  --comment <comment>     Comment to add before closing
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --pr 42
  $0 --repo itsdarklikehell/hermes-agent --pr 10 --comment "Superseded by #43"
EOF
}

REPO=""
PR=""
COMMENT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --comment) COMMENT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$PR" ] && { echo "Error: --pr is required" >&2; usage; exit 1; }

log "=== PR Close: $REPO#$PR ==="

# Add comment first if provided
if [ -n "$COMMENT" ]; then
  if maybe_mutate gh pr comment "$PR" --repo "$REPO" --body "$COMMENT"; then
    log "  ✓ Comment toegevoegd aan PR #$PR"
  else
    log "  ✗ Comment toevoegen failed voor PR #$PR"
  fi
fi

# Close the PR
if maybe_mutate gh pr close "$PR" --repo "$REPO"; then
  log "  ✓ PR #$PR gesloten in $REPO"
  send_telegram_message "🔒 *PR Closed*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
else
  log "  ✗ PR close failed voor $REPO#$PR"
  send_telegram_message "❌ *PR Close Failed*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
  exit 1
fi
