#!/usr/bin/env bash
# scripts/inbox-manager.sh - GitHub Inbox Manager
# Werkt zonder notification scope - gebruik gh search en gh issue/pr list
# Classificeert items, voegt labels/assignees toe, antwoordt op nieuwe issues

source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== GitHub Inbox Manager (search-based) ==="

# Configuratie
AUTO_LABEL_ENABLED="${AUTO_LABEL_ENABLED:-yes}"
AUTO_ASSIGN_ENABLED="${AUTO_ASSIGN_ENABLED:-yes}"
AUTO_REPLY_ENABLED="${AUTO_REPLY_ENABLED:-yes}"
TELEGRAM_REPORT_ENABLED="${TELEGRAM_REPORT_ENABLED:-yes}"

# Standaard antwoorden
REPLY_BUG="🐛 Thanks for reporting this bug! I'll investigate and get back to you soon."
REPLY_FEATURE="✨ Thanks for the feature request! I'll review this and add it to the backlog."
REPLY_QUESTION="❓ Thanks for your question! I'll look into this and respond as soon as possible."
REPLY_DEFAULT="👋 Thanks for reaching out! I'll review this and get back to you soon."

# Functies
classify_item() {
  local title="$1"
  local body="${2:-}"
  local combined="$title $body"
  
  if echo "$combined" | grep -qiE "bug|fix|error|crash|broken|regression|not working|fails"; then
    echo "bug"
  elif echo "$combined" | grep -qiE "feature|enhancement|add|request|suggest|would be nice|could you"; then
    echo "feature"
  elif echo "$combined" | grep -qiE "question|how|what|why|when|where|help|wondering"; then
    echo "question"
  elif echo "$combined" | grep -qiE "doc|readme|typo|documentation"; then
    echo "documentation"
  elif echo "$combined" | grep -ciE "security|vuln|cve|exploit|injection"; then
    echo "security"
  elif echo "$combined" | grep -ciE "performance|slow|optimi|speed|memory"; then
    echo "performance"
  elif echo "$combined" | grep -ciE "test|spec|coverage"; then
    echo "testing"
  elif echo "$combined" | grep -ciE "refactor|cleanup|simplify"; then
    echo "refactor"
  elif echo "$combined" | grep -ciE "dependenc|upgrade|update|bump"; then
    echo "dependencies"
  else
    echo "other"
  fi
}

get_label_for_category() {
  local category="$1"
  case "$category" in
    bug) echo "bug" ;;
    feature) echo "enhancement" ;;
    question) echo "question" ;;
    documentation) echo "documentation" ;;
    security) echo "security" ;;
    performance) echo "performance" ;;
    testing) echo "testing" ;;
    refactor) echo "refactor" ;;
    dependencies) echo "dependencies" ;;
    *) echo "triage" ;;
  esac
}

get_assignee_for_repo() {
  local repo="$1"
  case "$repo" in
    *hermes-desktop*|*mission-control*) echo "itsdarklikehell" ;;
    *dnd-utils*) echo "itsdarklikehell" ;;
    *hermes-agent*) echo "itsdarklikehell" ;;
    *clawhub*) echo "itsdarklikehell" ;;
    *ci-templates*) echo "itsdarklikehell" ;;
    *) echo "itsdarklikehell" ;;
  esac
}

get_reply_for_category() {
  local category="$1"
  case "$category" in
    bug) echo "$REPLY_BUG" ;;
    feature) echo "$REPLY_FEATURE" ;;
    question) echo "$REPLY_QUESTION" ;;
    *) echo "$REPLY_DEFAULT" ;;
  esac
}

# Fase 1: Eigen issues en PRs ophalen via gh search
log "Fase 1: Eigen issues en PRs ophalen via gh search..."

total_issues=0
total_prs=0
auto_labeled=0
auto_assigned=0
auto_replied=0
needs_attention=0

# Eigen issues via gh search
log "  Ophalen eigen issues via gh search..."
my_issues=$(gh search issues --state open --author @me --limit 50 --json title,repository,url,body,number 2>/dev/null || echo "[]")

# Eigen PRs via gh search
log "  Ophalen eigen PRs via gh search..."
my_prs=$(gh search prs --state open --author @me --limit 50 --json title,repository,url,body,number 2>/dev/null || echo "[]")

# Fase 2: Verwerk eigen issues
log "Fase 2: Verwerk eigen issues..."

if [ "$my_issues" != "[]" ] && [ -n "$my_issues" ]; then
  echo "$my_issues" | jq -c '.[]' 2>/dev/null | while IFS= read -r issue; do
    [ -z "$issue" ] && continue
    total_issues=$((total_issues + 1))
    
    title=$(echo "$issue" | jq -r '.title // "unknown"')
    repo=$(echo "$issue" | jq -r '.repository.nameWithOwner // "unknown"')
    url=$(echo "$issue" | jq -r '.url // ""')
    body=$(echo "$issue" | jq -r '.body // ""')
    number=$(echo "$issue" | jq -r '.number // ""')
    
    log "  [$total_issues] $repo#$number: $title"
    
    # Classificeer
    category=$(classify_item "$title" "$body")
    label=$(get_label_for_category "$category")
    log "    → Categorie: $category (label: $label)"
    
    # Voeg label toe
    if [ "$AUTO_LABEL_ENABLED" = "yes" ] && [ -n "$number" ]; then
      if gh issue edit "$repo#$number" --add-label "$label" 2>/dev/null; then
        log "    ✓ Label '$label' toegevoegd"
        auto_labeled=$((auto_labeled + 1))
      else
        log "    ⚠ Kon label niet toevoegen (mogelijk al aanwezig)"
      fi
    fi
    
    # Voeg assignee toe
    if [ "$AUTO_ASSIGN_ENABLED" = "yes" ] && [ -n "$number" ]; then
      assignee=$(get_assignee_for_repo "$repo")
      if gh issue edit "$repo#$number" --add-assignee "$assignee" 2>/dev/null; then
        log "    ✓ Assignee '$assignee' toegevoegd"
        auto_assigned=$((auto_assigned + 1))
      else
        log "    ⚠ Kon assignee niet toevoegen"
      fi
    fi
    
    # Antwoord op nieuwe issues
    if [ "$AUTO_REPLY_ENABLED" = "yes" ] && [ -n "$number" ]; then
      reply=$(get_reply_for_category "$category")
      if gh issue comment "$repo#$number" --body "$reply" 2>/dev/null; then
        log "    ✓ Antwoord geplaatst"
        auto_replied=$((auto_replied + 1))
      else
        log "    ⚠ Kon niet antwoorden"
      fi
    fi
  done
fi

# Fase 3: Verwerk eigen PRs
log "Fase 3: Verwerk eigen PRs..."

if [ "$my_prs" != "[]" ] && [ -n "$my_prs" ]; then
  echo "$my_prs" | jq -c '.[]' 2>/dev/null | while IFS= read -r pr; do
    [ -z "$pr" ] && continue
    total_prs=$((total_prs + 1))
    
    title=$(echo "$pr" | jq -r '.title // "unknown"')
    repo=$(echo "$pr" | jq -r '.repository.nameWithOwner // "unknown"')
    url=$(echo "$pr" | jq -r '.url // ""')
    body=$(echo "$pr" | jq -r '.body // ""')
    number=$(echo "$pr" | jq -r '.number // ""')
    
    log "  [$total_prs] PR $repo#$number: $title"
    
    # Classificeer
    category=$(classify_item "$title" "$body")
    label=$(get_label_for_category "$category")
    log "    → Categorie: $category (label: $label)"
    
    # Voeg label toe
    if [ "$AUTO_LABEL_ENABLED" = "yes" ] && [ -n "$number" ]; then
      if gh pr edit "$repo#$number" --add-label "$label" 2>/dev/null; then
        log "    ✓ Label '$label' toegevoegd"
        auto_labeled=$((auto_labeled + 1))
      else
        log "    ⚠ Kon label niet toevoegen"
      fi
    fi
    
    # Voeg assignee toe
    if [ "$AUTO_ASSIGN_ENABLED" = "yes" ] && [ -n "$number" ]; then
      assignee=$(get_assignee_for_repo "$repo")
      if gh pr edit "$repo#$number" --add-assignee "$assignee" 2>/dev/null; then
        log "    ✓ Assignee '$assignee' toegevoegd"
        auto_assigned=$((auto_assigned + 1))
      else
        log "    ⚠ Kon assignee niet toevoegen"
      fi
    fi
    
    # Markeer als needs-attention
    needs_attention=$((needs_attention + 1))
  done
fi

# Fase 4: Doorloop bekende repos voor open issues en PRs
log "Fase 4: Doorloop bekende repos..."

for repo in "${KEY_REPOS[@]}"; do
  log "  Repo: $repo"
  
  # Open issues
  repo_issues=$(gh issue list --repo "$repo" --state open --limit 20 --json title,number,body,url 2>/dev/null || echo "[]")
  if [ "$repo_issues" != "[]" ] && [ -n "$repo_issues" ]; then
    echo "$repo_issues" | jq -c '.[]' 2>/dev/null | while IFS= read -r issue; do
      [ -z "$issue" ] && continue
      total_issues=$((total_issues + 1))
      
      title=$(echo "$issue" | jq -r '.title // "unknown"')
      number=$(echo "$issue" | jq -r '.number // ""')
      body=$(echo "$issue" | jq -r '.body // ""')
      
      log "    Issue #$number: $title"
      
      category=$(classify_item "$title" "$body")
      label=$(get_label_for_category "$category")
      
      if [ "$AUTO_LABEL_ENABLED" = "yes" ] && [ -n "$number" ]; then
        gh issue edit "$repo#$number" --add-label "$label" 2>/dev/null && auto_labeled=$((auto_labeled + 1)) || true
      fi
      
      if [ "$AUTO_ASSIGN_ENABLED" = "yes" ] && [ -n "$number" ]; then
        assignee=$(get_assignee_for_repo "$repo")
        gh issue edit "$repo#$number" --add-assignee "$assignee" 2>/dev/null && auto_assigned=$((auto_assigned + 1)) || true
      fi
      
      if [ "$AUTO_REPLY_ENABLED" = "yes" ] && [ -n "$number" ]; then
        reply=$(get_reply_for_category "$category")
        gh issue comment "$repo#$number" --body "$reply" 2>/dev/null && auto_replied=$((auto_replied + 1)) || true
      fi
    done
  fi
  
  # Open PRs
  repo_prs=$(gh pr list --repo "$repo" --state open --limit 20 --json title,number,body,url 2>/dev/null || echo "[]")
  if [ "$repo_prs" != "[]" ] && [ -n "$repo_prs" ]; then
    echo "$repo_prs" | jq -c '.[]' 2>/dev/null | while IFS= read -r pr; do
      [ -z "$pr" ] && continue
      total_prs=$((total_prs + 1))
      
      title=$(echo "$pr" | jq -r '.title // "unknown"')
      number=$(echo "$pr" | jq -r '.number // ""')
      body=$(echo "$pr" | jq -r '.body // ""')
      
      log "    PR #$number: $title"
      
      category=$(classify_item "$title" "$body")
      label=$(get_label_for_category "$category")
      
      if [ "$AUTO_LABEL_ENABLED" = "yes" ] && [ -n "$number" ]; then
        gh pr edit "$repo#$number" --add-label "$label" 2>/dev/null && auto_labeled=$((auto_labeled + 1)) || true
      fi
      
      if [ "$AUTO_ASSIGN_ENABLED" = "yes" ] && [ -n "$number" ]; then
        assignee=$(get_assignee_for_repo "$repo")
        gh pr edit "$repo#$number" --add-assignee "$assignee" 2>/dev/null && auto_assigned=$((auto_assigned + 1)) || true
      fi
      
      needs_attention=$((needs_attention + 1))
    done
  fi
done

# Fase 5: Samenvatting
log "Fase 5: Samenvatting..."
log "  Totaal issues verwerkt: $total_issues"
log "  Totaal PRs verwerkt: $total_prs"
log "  Automatisch labels toegevoegd: $auto_labeled"
log "  Automatisch assignees toegevoegd: $auto_assigned"
log "  Automatisch antwoorden geplaatst: $auto_replied"
log "  Nodig aandacht: $needs_attention"

log "=== GitHub Inbox Manager complete ==="

# Telegram rapportage
if [ "$TELEGRAM_REPORT_ENABLED" = "yes" ]; then
  send_telegram_message "📬 *GitHub Inbox Manager* (search-based)

*Issues verwerkt:* $total_issues
*PRs verwerkt:* $total_prs
*Labels toegevoegd:* $auto_labeled
*Assignees toegevoegd:* $auto_assigned
*Antwoorden geplaatst:* $auto_replied
*Aandacht nodig:* $needs_attention

📋 Volledig log: $LOG_FILE" || true
fi
