#!/usr/bin/env bash
# lib/config.sh - Configuratie voor GitHub Fleet Manager

REPOS_DIR="${REPOS_DIR:-$HOME/.openclaw/workspace/projects}"
LOG_FILE="${LOG_FILE:-$HOME/.github_fleet_manager.log}"
PARALLEL_JOBS="${PARALLEL_JOBS:-8}"

# Telegram configuratie
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-${GITHUB_FLEET_TELEGRAM_TOKEN:-${TELEGRAM_BOT_TOKEN:-}}}"
CHAT_ID="${CHAT_ID:-${GITHUB_FLEET_CHAT_ID:-${TELEGRAM_HOME_CHANNEL:-1779426583}}}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-1779426583 -1004424968209 639276511}"

# Auto-pilot configuratie
AUTO_MERGE_ENABLED="${AUTO_MERGE_ENABLED:-yes}"
STALE_CLOSE_DAYS="${STALE_CLOSE_DAYS:-30}"
AUTO_RERUN_REPOS=( ${AUTO_RERUN_REPOS:-itsdarklikehell/hermes-desktop itsdarklikehell/mission-control itsdarklikehell/hermes-pixel-office-enhanced itsdarklikehell/dnd-utils} )
SYNC_FORKS_ENABLED="${SYNC_FORKS_ENABLED:-yes}"
CLEAN_BRANCHES_REPOS=( ${CLEAN_BRANCHES_REPOS:-itsdarklikehell/hermes-desktop itsdarklikehell/mission-control itsdarklikehell/dnd-utils itsdarklikehell/ci-templates itsdarklikehell/hermes-pixel-office-enhanced} )
LABEL_TRIAGE_ENABLED="${LABEL_TRIAGE_ENABLED:-yes}"
RELEASE_REPOS=( ${RELEASE_REPOS:-itsdarklikehell/hermes-desktop itsdarklikehell/mission-control itsdarklikehell/dnd-utils itsdarklikehell/hermes-agent itsdarklikehell/clawhub} )
KEY_REPOS=( ${KEY_REPOS:-itsdarklikehell/hermes-desktop itsdarklikehell/mission-control itsdarklikehell/dnd-utils itsdarklikehell/hermes-agent itsdarklikehell/clawhub itsdarklikehell/hermes-pixel-office-enhanced} )

# Audit configuratie
SECURITY_AUDIT_ENABLED="${SECURITY_AUDIT_ENABLED:-yes}"
BRANCH_PROTECTION_ENABLED="${BRANCH_PROTECTION_ENABLED:-yes}"
PAGES_CHECK_ENABLED="${PAGES_CHECK_ENABLED:-yes}"
WIKIS_CHECK_ENABLED="${WIKIS_CHECK_ENABLED:-yes}"
TOPICS_AUDIT_ENABLED="${TOPICS_AUDIT_ENABLED:-yes}"
RELEASE_ASSET_CHECK_ENABLED="${RELEASE_ASSET_CHECK_ENABLED:-yes}"
DISABLED_WORKFLOWS_ENABLED="${DISABLED_WORKFLOWS_ENABLED:-yes}"
COLLABORATOR_AUDIT_ENABLED="${COLLABORATOR_AUDIT_ENABLED:-yes}"
RANKING_ENABLED="${RANKING_ENABLED:-yes}"
REPO_FEATURES_ENABLED="${REPO_FEATURES_ENABLED:-yes}"
SECURITY_AUDIT_ALL_REPOS="${SECURITY_AUDIT_ALL_REPOS:-no}"
DRY_RUN="${GITHUB_FLEET_DRY_RUN:-}"

# Extended audit configuratie
CODEOWNERS_AUDIT_ENABLED="${CODEOWNERS_AUDIT_ENABLED:-yes}"
CONTRIB_LICENSE_AUDIT_ENABLED="${CONTRIB_LICENSE_AUDIT_ENABLED:-yes}"
PR_SIZE_MONITOR_ENABLED="${PR_SIZE_MONITOR_ENABLED:-yes}"
PR_SIZE_THRESHOLD="${PR_SIZE_THRESHOLD:-500}"
COMMIT_ACTIVITY_ENABLED="${COMMIT_ACTIVITY_ENABLED:-yes}"
COMMIT_ACTIVITY_DAYS="${COMMIT_ACTIVITY_DAYS:-30}"
CONTRIB_FILES=("CONTRIBUTING.md" "LICENSE" "SECURITY.md" "CODE_OF_CONDUCT.md" "SUPPORT.md")

# Dual auth (hmol33)
HMOL33_TOKEN=""
if [ -f "$HOME/.hermes/.env" ]; then
  HMOL33_TOKEN=$(grep "^GH_TOKEN_HMOL33=" "$HOME/.hermes/.env" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || echo "")
fi
if [ -z "$HMOL33_TOKEN" ] || [ "${#HMOL33_TOKEN}" -lt 10 ] || [ "$HMOL33_TOKEN" = "***" ]; then
  HMOL33_TOKEN=""
fi

# Functies
set_repo_token() {
  local org="$1"
  if [ "$org" = "hmol33" ] && [ -n "$HMOL33_TOKEN" ]; then
    export GITHUB_TOKEN="$HMOL33_TOKEN"
  else
    unset GITHUB_TOKEN
  fi
}

gh_for_repo() {
  local repo_dir="$1"; shift
  local org
  org=$(get_repo_org "$repo_dir")
  if [ "$org" = "hmol33" ] && [ -n "$HMOL33_TOKEN" ]; then
    GITHUB_TOKEN="$HMOL33_TOKEN" gh "$@"
  else
    gh "$@"
  fi
}

get_repo_org() {
  local dir="$1"
  local org=""
  local origin_url
  origin_url=$(cd "$dir" && git remote get-url origin 2>/dev/null || echo "")
  if [ -n "$origin_url" ]; then
    org=$(echo "$origin_url" | sed -n 's|.*github.com/\([^/]*\)/.*|\1|p')
  fi
  if [ -z "$org" ] || [ "$org" = "fork" ]; then
    local upstream_url
    upstream_url=$(cd "$dir" && git remote get-url upstream 2>/dev/null || echo "")
    if [ -n "$upstream_url" ]; then
      local uorg
      uorg=$(echo "$upstream_url" | sed -n 's|.*github.com/\([^/]*\)/.*|\1|p')
      if [ -n "$uorg" ] && [ "$uorg" != "fork" ]; then
        org="$uorg"
      fi
    fi
  fi
  echo "${org:-itsdarklikehell}"
}

find_upstream() {
  local dir="$1"; local upstream=""
  for r in $(cd "$dir" && git remote 2>/dev/null); do
    if [ "$r" != "origin" ]; then upstream="$r"; break; fi
  done
  echo "$upstream"
}

log() {
  local msg="$*"; local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  local lockfile="$LOG_FILE.lock"
  local waited=0
  while [ -f "$lockfile" ] && [ $waited -lt 50 ]; do
    sleep 0.1; ((waited++)) || true
  done
  echo "[$ts] $msg" >> "$LOG_FILE" 2>/dev/null || echo "[$ts] $msg"
  rm -f "$lockfile" 2>/dev/null || true
}

report() { echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $*"; }

maybe_mutate() {
  if [ -n "${GITHUB_FLEET_DRY_RUN:-}" ]; then
    log "🔒 [DRY-RUN] Would: $*"
    return 0
  fi
  "$@"
}
