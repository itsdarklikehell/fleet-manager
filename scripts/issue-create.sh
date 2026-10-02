#!/usr/bin/env bash
# scripts/issue-create.sh - Create issues vanuit templates
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --title <title> [--body <body>] [--template <template>] [--label <label>]... [--assignee <user>]... [--milestone <milestone>]

Create a new issue in a GitHub repository.

Options:
  --repo <org/repo>       Repository (required)
  --title <title>         Issue title (required)
  --body <body>           Issue body text
  --template <template>   Issue template file (e.g., .github/ISSUE_TEMPLATE/bug_report.md)
  --label <label>         Label to add (can be repeated)
  --assignee <user>       Assignee username (can be repeated)
  --milestone <milestone> Milestone title
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --title "Bug: crash on startup" --label bug
  $0 --repo itsdarklikehell/hermes-agent --title "Feature: dark mode" --template feature_request.md --assignee hmol33
EOF
}

REPO=""
TITLE=""
BODY=""
TEMPLATE=""
LABELS=()
ASSIGNEES=""
MILESTONE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --label) LABELS+=("$2"); shift 2 ;;
    --assignee) ASSIGNEES="$ASSIGNEES $2"; shift 2 ;;
    --milestone) MILESTONE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$TITLE" ] && { echo "Error: --title is required" >&2; usage; exit 1; }

log "=== Issue Create: $REPO ==="

# Build gh command
args=(issue create --repo "$REPO" --title "$TITLE")

if [ -n "$TEMPLATE" ]; then
  if [ -f "$TEMPLATE" ]; then
    args+=(--body "$(cat "$TEMPLATE")")
  else
    # Try as a template name in .github/ISSUE_TEMPLATE/
    args+=(--template "$TEMPLATE")
  fi
elif [ -n "$BODY" ]; then
  args+=(--body "$BODY")
fi

for label in "${LABELS[@]}"; do
  args+=(--label "$label")
done

for assignee in $ASSIGNEES; do
  args+=(--assignee "$assignee")
done

[ -n "$MILESTONE" ] && args+=(--milestone "$MILESTONE")

if maybe_mutate gh "${args[@]}"; then
  log "  ✓ Issue aangemaakt in $REPO: $TITLE"
  send_telegram_message "📝 *Issue Created*\n\n*Repo:* \`$REPO\`\n*Title:* $TITLE" || true
else
  log "  ✗ Issue create failed voor $REPO: $TITLE"
  send_telegram_message "❌ *Issue Create Failed*\n\n*Repo:* \`$REPO\`\n*Title:* $TITLE" || true
  exit 1
fi
