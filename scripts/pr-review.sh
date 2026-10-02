#!/usr/bin/env bash
# scripts/pr-review.sh - Review PRs (approve, request changes, comment)
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --pr <number> --action <approve|request-changes|comment> [--body <body>]

Review a pull request.

Options:
  --repo <org/repo>       Repository (required)
  --pr <number>           PR number (required)
  --action <action>       Review action: approve, request-changes, or comment (required)
  --body <body>           Review body text (required for approve/request-changes/comment)
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --pr 42 --action approve --body "LGTM!"
  $0 --repo itsdarklikehell/hermes-agent --pr 10 --action request-changes --body "Please fix the tests"
  $0 --repo itsdarklikehell/hermes-desktop --pr 42 --action comment --body "Nice work!"
EOF
}

REPO=""
PR=""
ACTION=""
BODY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --action) ACTION="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$PR" ] && { echo "Error: --pr is required" >&2; usage; exit 1; }
[ -z "$ACTION" ] && { echo "Error: --action is required" >&2; usage; exit 1; }
[ -z "$BODY" ] && { echo "Error: --body is required" >&2; usage; exit 1; }

log "=== PR Review: $REPO#$PR ==="

args=(pr review "$PR" --repo "$REPO")

case "$ACTION" in
  approve) args+=(--approve --body "$BODY") ;;
  request-changes) args+=(--request-changes --body "$BODY") ;;
  comment) args+=(--comment --body "$BODY") ;;
  *) echo "Error: invalid action '$ACTION' (use approve, request-changes, or comment)" >&2; exit 1 ;;
esac

if maybe_mutate gh "${args[@]}"; then
  log "  ✓ PR #$PR reviewed in $REPO (action: $ACTION)"
  case "$ACTION" in
    approve) emoji="✅" ;;
    request-changes) emoji="🔄" ;;
    comment) emoji="💬" ;;
  esac
  send_telegram_message "$emoji *PR Review*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR\n*Action:* $ACTION" || true
else
  log "  ✗ PR review failed voor $REPO#$PR"
  send_telegram_message "❌ *PR Review Failed*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
  exit 1
fi
