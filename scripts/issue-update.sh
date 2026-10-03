#!/usr/bin/env bash
# scripts/issue-update.sh - Update issues (labels, assignees, milestones)
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --issue <number> [--title <title>] [--body <body>] [--add-label <label>]... [--remove-label <label>]... [--add-assignee <user>]... [--remove-assignee <user>]... [--milestone <milestone>] [--state <open|closed>]

Update an existing issue.

Options:
  --repo <org/repo>              Repository (required)
  --issue <number>               Issue number (required)
  --title <title>                New title
  --body <body>                  New body
  --add-label <label>            Add label (can be repeated)
  --remove-label <label>         Remove label (can be repeated)
  --add-assignee <user>          Add assignee (can be repeated)
  --remove-assignee <user>       Remove assignee (can be repeated)
  --milestone <milestone>        Set milestone
  --state <open|closed>          Set state
  -h, --help                     Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --issue 42 --title "New title" --add-label bug
  $0 --repo itsdarklikehell/hermes-agent --issue 10 --remove-label stale --milestone "v2.0"
EOF
}

REPO=""
ISSUE=""
TITLE=""
BODY=""
ADD_LABELS=()
REMOVE_LABELS=()
ADD_ASSIGNEES=""
REMOVE_ASSIGNEES=""
MILESTONE=""
STATE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --issue) ISSUE="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --add-label) ADD_LABELS+=("$2"); shift 2 ;;
    --remove-label) REMOVE_LABELS+=("$2"); shift 2 ;;
    --add-assignee) ADD_ASSIGNEES="$ADD_ASSIGNEES $2"; shift 2 ;;
    --remove-assignee) REMOVE_ASSIGNEES="$REMOVE_ASSIGNEES $2"; shift 2 ;;
    --milestone) MILESTONE="$2"; shift 2 ;;
    --state) STATE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$ISSUE" ] && { echo "Error: --issue is required" >&2; usage; exit 1; }

log "=== Issue Update: $REPO#$ISSUE ==="

# Build edit command
args=(issue edit "$ISSUE" --repo "$REPO")

[ -n "$TITLE" ] && args+=(--title "$TITLE")
[ -n "$BODY" ] && args+=(--body "$BODY")
[ -n "$MILESTONE" ] && args+=(--milestone "$MILESTONE")
[ -n "$STATE" ] && args+=(--state "$STATE")

for label in "${ADD_LABELS[@]}"; do
  args+=(--add-label "$label")
done

for label in "${REMOVE_LABELS[@]}"; do
  args+=(--remove-label "$label")
done

for assignee in $ADD_ASSIGNEES; do
  args+=(--add-assignee "$assignee")
done

for assignee in $REMOVE_ASSIGNEES; do
  args+=(--remove-assignee "$assignee")
done

if maybe_mutate gh "${args[@]}"; then
  log "  ✓ Issue #$ISSUE geüpdatet in $REPO"
  send_telegram_message "✏️ *Issue Updated*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE" || true
else
  log "  ✗ Issue update failed voor $REPO#$ISSUE"
  send_telegram_message "❌ *Issue Update Failed*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE" || true
  exit 1
fi
