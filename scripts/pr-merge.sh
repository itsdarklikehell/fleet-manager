#!/usr/bin/env bash
# scripts/pr-merge.sh - Merge PRs (merge, squash, rebase)
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --pr <number> [--method <merge|squash|rebase>] [--subject <subject>] [--body <body>] [--delete-branch] [--auto]

Merge a pull request.

Options:
  --repo <org/repo>       Repository (required)
  --pr <number>           PR number (required)
  --method <method>       Merge method: merge, squash (default), or rebase
  --subject <subject>     Custom merge commit subject
  --body <body>           Custom merge commit body
  --delete-branch         Delete head branch after merge
  --auto                  Enable auto-merge
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --pr 42 --method squash --delete-branch
  $0 --repo itsdarklikehell/hermes-agent --pr 10 --method merge
  $0 --repo itsdarklikehell/hermes-desktop --pr 42 --method rebase --auto
EOF
}

REPO=""
PR=""
METHOD="squash"
SUBJECT=""
BODY=""
DELETE_BRANCH=0
AUTO=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --method) METHOD="$2"; shift 2 ;;
    --subject) SUBJECT="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --delete-branch) DELETE_BRANCH=1; shift ;;
    --auto) AUTO=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$PR" ] && { echo "Error: --pr is required" >&2; usage; exit 1; }

log "=== PR Merge: $REPO#$PR ==="

args=(pr merge "$PR" --repo "$REPO")

case "$METHOD" in
  merge) args+=(--merge) ;;
  squash) args+=(--squash) ;;
  rebase) args+=(--rebase) ;;
  *) echo "Error: invalid method '$METHOD' (use merge, squash, or rebase)" >&2; exit 1 ;;
esac

[ -n "$SUBJECT" ] && args+=(--subject "$SUBJECT")
[ -n "$BODY" ] && args+=(--body "$BODY")
[ "$DELETE_BRANCH" -eq 1 ] && args+=(--delete-branch)
[ "$AUTO" -eq 1 ] && args+=(--auto)

if maybe_mutate gh "${args[@]}"; then
  log "  ✓ PR #$PR gemerged in $REPO (method: $METHOD)"
  send_telegram_message "🔀 *PR Merged*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR\n*Method:* $METHOD" || true
else
  log "  ✗ PR merge failed voor $REPO#$PR"
  send_telegram_message "❌ *PR Merge Failed*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
  exit 1
fi
