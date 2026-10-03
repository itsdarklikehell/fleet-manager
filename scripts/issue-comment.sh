#!/usr/bin/env bash
# scripts/issue-comment.sh - Add comments to issues
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --issue <number> --body <body> [--file <file>]

Add a comment to an issue.

Options:
  --repo <org/repo>       Repository (required)
  --issue <number>        Issue number (required)
  --body <body>           Comment body text (required unless --file is used)
  --file <file>           Read comment body from file
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --issue 42 --body "This is a comment"
  $0 --repo itsdarklikehell/hermes-agent --issue 10 --file /tmp/comment.md
EOF
}

REPO=""
ISSUE=""
BODY=""
FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --issue) ISSUE="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$ISSUE" ] && { echo "Error: --issue is required" >&2; usage; exit 1; }

if [ -n "$FILE" ]; then
  [ -f "$FILE" ] || { echo "Error: file not found: $FILE" >&2; exit 1; }
  BODY=$(cat "$FILE")
fi

[ -z "$BODY" ] && { echo "Error: --body or --file is required" >&2; usage; exit 1; }

log "=== Issue Comment: $REPO#$ISSUE ==="

if maybe_mutate gh issue comment "$ISSUE" --repo "$REPO" --body "$BODY"; then
  log "  ✓ Comment toegevoegd aan #$ISSUE in $REPO"
  send_telegram_message "💬 *Issue Comment*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE" || true
else
  log "  ✗ Comment toevoegen failed voor $REPO#$ISSUE"
  send_telegram_message "❌ *Issue Comment Failed*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE" || true
  exit 1
fi
