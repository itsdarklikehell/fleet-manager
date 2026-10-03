#!/usr/bin/env bash
# scripts/pr-comment.sh - Add comments to PRs
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --pr <number> --body <body> [--file <file>]

Add a comment to a pull request.

Options:
  --repo <org/repo>       Repository (required)
  --pr <number>           PR number (required)
  --body <body>           Comment body text (required unless --file is used)
  --file <file>           Read comment body from file
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --pr 42 --body "LGTM!"
  $0 --repo itsdarklikehell/hermes-agent --pr 10 --file /tmp/review.md
EOF
}

REPO=""
PR=""
BODY=""
FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$PR" ] && { echo "Error: --pr is required" >&2; usage; exit 1; }

if [ -n "$FILE" ]; then
  [ -f "$FILE" ] || { echo "Error: file not found: $FILE" >&2; exit 1; }
  BODY=$(cat "$FILE")
fi

[ -z "$BODY" ] && { echo "Error: --body or --file is required" >&2; usage; exit 1; }

log "=== PR Comment: $REPO#$PR ==="

if maybe_mutate gh pr comment "$PR" --repo "$REPO" --body "$BODY"; then
  log "  ✓ Comment toegevoegd aan PR #$PR in $REPO"
  send_telegram_message "💬 *PR Comment*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
else
  log "  ✗ Comment toevoegen failed voor $REPO#$PR"
  send_telegram_message "❌ *PR Comment Failed*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
  exit 1
fi
