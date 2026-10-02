#!/usr/bin/env bash
# scripts/pr-reopen.sh - Reopen PRs
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --pr <number> [--comment <comment>]

Reopen a closed pull request.

Options:
  --repo <org/repo>       Repository (required)
  --pr <number>           PR number (required)
  --comment <comment>     Comment to add when reopening
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --pr 42
  $0 --repo itsdarklikehell/hermes-agent --pr 10 --comment "Reopening — still relevant"
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

log "=== PR Reopen: $REPO#$PR ==="

# Add comment first if provided
if [ -n "$COMMENT" ]; then
  if maybe_mutate gh pr comment "$PR" --repo "$REPO" --body "$COMMENT"; then
    log "  ✓ Comment toegevoegd aan PR #$PR"
  else
    log "  ✗ Comment toevoegen failed voor PR #$PR"
  fi
fi

# Reopen the PR
if maybe_mutate gh pr reopen "$PR" --repo "$REPO"; then
  log "  ✓ PR #$PR heropend in $REPO"
  send_telegram_message "🔓 *PR Reopened*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
else
  log "  ✗ PR reopen failed voor $REPO#$PR"
  send_telegram_message "❌ *PR Reopen Failed*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
  exit 1
fi
