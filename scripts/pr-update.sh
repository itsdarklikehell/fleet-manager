#!/usr/bin/env bash
# scripts/pr-update.sh - Update PRs (title, body, labels, assignees)
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --pr <number> [--title <title>] [--body <body>] [--add-label <label>]... [--remove-label <label>]... [--add-assignee <user>]... [--remove-assignee <user>]... [--add-reviewer <user>]... [--remove-reviewer <user>]... [--base <branch>] [--state <open|closed>]

Update an existing pull request.

Options:
  --repo <org/repo>              Repository (required)
  --pr <number>                  PR number (required)
  --title <title>                New title
  --body <body>                  New body
  --add-label <label>            Add label (can be repeated)
  --remove-label <label>         Remove label (can be repeated)
  --add-assignee <user>          Add assignee (can be repeated)
  --remove-assignee <user>       Remove assignee (can be repeated)
  --add-reviewer <user>          Add reviewer (can be repeated)
  --remove-reviewer <user>       Remove reviewer (can be repeated)
  --base <branch>                Change base branch
  --state <open|closed>          Set state
  -h, --help                     Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --pr 42 --title "New title" --add-label bug
  $0 --repo itsdarklikehell/hermes-agent --pr 10 --remove-label stale --add-reviewer hmol33
EOF
}

REPO=""
PR=""
TITLE=""
BODY=""
ADD_LABELS=()
REMOVE_LABELS=()
ADD_ASSIGNEES=""
REMOVE_ASSIGNEES=""
ADD_REVIEWERS=""
REMOVE_REVIEWERS=""
BASE=""
STATE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --add-label) ADD_LABELS+=("$2"); shift 2 ;;
    --remove-label) REMOVE_LABELS+=("$2"); shift 2 ;;
    --add-assignee) ADD_ASSIGNEES="$ADD_ASSIGNEES $2"; shift 2 ;;
    --remove-assignee) REMOVE_ASSIGNEES="$REMOVE_ASSIGNEES $2"; shift 2 ;;
    --add-reviewer) ADD_REVIEWERS="$ADD_REVIEWERS $2"; shift 2 ;;
    --remove-reviewer) REMOVE_REVIEWERS="$REMOVE_REVIEWERS $2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --state) STATE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$PR" ] && { echo "Error: --pr is required" >&2; usage; exit 1; }

log "=== PR Update: $REPO#$PR ==="

args=(pr edit "$PR" --repo "$REPO")

[ -n "$TITLE" ] && args+=(--title "$TITLE")
[ -n "$BODY" ] && args+=(--body "$BODY")
[ -n "$BASE" ] && args+=(--base "$BASE")
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

for reviewer in $ADD_REVIEWERS; do
  args+=(--add-reviewer "$reviewer")
done

for reviewer in $REMOVE_REVIEWERS; do
  args+=(--remove-reviewer "$reviewer")
done

if maybe_mutate gh "${args[@]}"; then
  log "  ✓ PR #$PR geüpdatet in $REPO"
  send_telegram_message "✏️ *PR Updated*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
else
  log "  ✗ PR update failed voor $REPO#$PR"
  send_telegram_message "❌ *PR Update Failed*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
  exit 1
fi
