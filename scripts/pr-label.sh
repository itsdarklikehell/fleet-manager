#!/usr/bin/env bash
# scripts/pr-label.sh - Add/remove labels from PRs
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --pr <number> --add <label>... [--remove <label>...]

Add or remove labels from a pull request.

Options:
  --repo <org/repo>       Repository (required)
  --pr <number>           PR number (required)
  --add <label>           Label to add (can be repeated)
  --remove <label>        Label to remove (can be repeated)
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --pr 42 --add bug --add urgent
  $0 --repo itsdarklikehell/hermes-agent --pr 10 --remove stale
  $0 --repo itsdarklikehell/hermes-desktop --pr 42 --add bug --remove stale
EOF
}

REPO=""
PR=""
ADD_LABELS=""
REMOVE_LABELS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --add) ADD_LABELS="$ADD_LABELS $2"; shift 2 ;;
    --remove) REMOVE_LABELS="$REMOVE_LABELS $2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1;}
[ -z "$PR" ] && { echo "Error: --pr is required" >&2; usage; exit 1; }
[ -z "$ADD_LABELS" ] && [ -z "$REMOVE_LABELS" ] && { echo "Error: --add or --remove is required" >&2; usage; exit 1; }

log "=== PR Label: $REPO#$PR ==="

args=(pr edit "$PR" --repo "$REPO")

for label in $ADD_LABELS; do
  args+=(--add-label "$label")
done

for label in $REMOVE_LABELS; do
  args+=(--remove-label "$label")
done

if maybe_mutate gh "${args[@]}"; then
  log "  ✓ Labels bijgewerkt voor PR #$PR in $REPO"
  msg="🏷️ *PR Labels Updated*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR"
  [ -n "$ADD_LABELS" ] && msg="$msg\n*Added:*$ADD_LABELS"
  [ -n "$REMOVE_LABELS" ] && msg="$msg\n*Removed:*$REMOVE_LABELS"
  send_telegram_message "$msg" || true
else
  log "  ✗ PR label update failed voor $REPO#$PR"
  send_telegram_message "❌ *PR Label Failed*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
  exit 1
fi
