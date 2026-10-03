#!/usr/bin/env bash
# scripts/issue-assign.sh - Assign issues to users
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --issue <number> --assignee <user>... [--remove]

Assign or unassign users from an issue.

Options:
  --repo <org/repo>       Repository (required)
  --issue <number>        Issue number (required)
  --assignee <user>       Username to assign (can be repeated, required unless --remove)
  --remove                Remove assignees instead of adding
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --issue 42 --assignee hmol33
  $0 --repo itsdarklikehell/hermes-agent --issue 10 --assignee hmol33 --assignee user2
  $0 --repo itsdarklikehell/hermes-desktop --issue 42 --assignee hmol33 --remove
EOF
}

REPO=""
ISSUE=""
ASSIGNEES=""
REMOVE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --issue) ISSUE="$2"; shift 2 ;;
    --assignee) ASSIGNEES="$ASSIGNEES $2"; shift 2 ;;
    --remove) REMOVE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$ISSUE" ] && { echo "Error: --issue is required" >&2; usage; exit 1; }
[ -z "$ASSIGNEES" ] && { echo "Error: --assignee is required" >&2; usage; exit 1; }

log "=== Issue Assign: $REPO#$ISSUE ==="

args=(issue edit "$ISSUE" --repo "$REPO")

if [ "$REMOVE" -eq 1 ]; then
  for assignee in $ASSIGNEES; do
    args+=(--remove-assignee "$assignee")
  done
else
  for assignee in $ASSIGNEES; do
    args+=(--add-assignee "$assignee")
  done
fi

if maybe_mutate gh "${args[@]}"; then
  if [ "$REMOVE" -eq 1 ]; then
    log "  ✓ Assignees verwijderd van #$ISSUE in $REPO"
    send_telegram_message "👤 *Issue Unassigned*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE" || true
  else
    log "  ✓ Issue #$ISSUE toegewezen in $REPO"
    send_telegram_message "👤 *Issue Assigned*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE\n*Assignees:*$ASSIGNEES" || true
  fi
else
  log "  ✗ Issue assign failed voor $REPO#$ISSUE"
  send_telegram_message "❌ *Issue Assign Failed*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE" || true
  exit 1
fi
