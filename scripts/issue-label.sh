#!/usr/bin/env bash
# scripts/issue-label.sh - Add/remove labels from issues
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --issue <number> --add <label>... [--remove <label>...]

Add or remove labels from an issue.

Options:
  --repo <org/repo>       Repository (required)
  --issue <number>        Issue number (required)
  --add <label>           Label to add (can be repeated)
  --remove <label>        Label to remove (can be repeated)
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --issue 42 --add bug --add urgent
  $0 --repo itsdarklikehell/hermes-agent --issue 10 --remove stale
  $0 --repo itsdarklikehell/hermes-desktop --issue 42 --add bug --remove stale
EOF
}

REPO=""
ISSUE=""
ADD_LABELS=""
REMOVE_LABELS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --issue) ISSUE="$2"; shift 2 ;;
    --add) ADD_LABELS="$ADD_LABELS $2"; shift 2 ;;
    --remove) REMOVE_LABELS="$REMOVE_LABELS $2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$ISSUE" ] && { echo "Error: --issue is required" >&2; usage; exit 1; }
[ -z "$ADD_LABELS" ] && [ -z "$REMOVE_LABELS" ] && { echo "Error: --add or --remove is required" >&2; usage; exit 1; }

log "=== Issue Label: $REPO#$ISSUE ==="

args=(issue edit "$ISSUE" --repo "$REPO")

for label in $ADD_LABELS; do
  args+=(--add-label "$label")
done

for label in $REMOVE_LABELS; do
  args+=(--remove-label "$label")
done

if maybe_mutate gh "${args[@]}"; then
  log "  ✓ Labels bijgewerkt voor #$ISSUE in $REPO"
  msg="🏷️ *Issue Labels Updated*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE"
  [ -n "$ADD_LABELS" ] && msg="$msg\n*Added:*$ADD_LABELS"
  [ -n "$REMOVE_LABELS" ] && msg="$msg\n*Removed:*$REMOVE_LABELS"
  send_telegram_message "$msg" || true
else
  log "  ✗ Issue label update failed voor $REPO#$ISSUE"
  send_telegram_message "❌ *Issue Label Failed*\n\n*Repo:* \`$REPO\`\n*Issue:* #$ISSUE" || true
  exit 1
fi
