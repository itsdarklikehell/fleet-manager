#!/usr/bin/env bash
# scripts/inbox-manager.sh - GitHub Inbox Manager
# Leest open issues/PRs, classificeert en antwoordt automatisch waar mogelijk
# Werkt zonder notification scope - gebruik gh search i.p.v. notifications API
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== GitHub Inbox Manager ==="

# Fase 1: Open items ophalen voor beide accounts
log "Fase 1: Open items ophalen..."

total_items=0
auto_handled=0
needs_attention=0

# Verwerk itsdarklikehell repos
log "  Verwerk itsdarklikehell repos..."
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir")
  
  # Sla fleet-manager over (die heeft al alles)
  [ "$repo" = "fleet-manager" ] && continue
  
  set_repo_token "$org"
  
  # Haal open issues op
  local_issues=$(gh issue list --repo "${org}/${repo}" --state open --json number,title,labels --limit 10 2>/dev/null || echo "[]")
  
  if [ "$local_issues" != "[]" ] && [ -n "$local_issues" ]; then
    while IFS= read -r issue; do
      [ -z "$issue" ] && continue
      total_items=$((total_items + 1))
      
      issue_num=$(echo "$issue" | jq -r '.number // "unknown"')
      issue_title=$(echo "$issue" | jq -r '.title // "unknown"')
      issue_labels=$(echo "$issue" | jq -r '.labels | length')
      
      log "  [$total_items] Issue #$issue_num: $issue_title (labels: $issue_labels)"
      
      # Voeg labels toe op basis van titel
      if [ "$issue_labels" = "0" ]; then
        if echo "$issue_title" | grep -qiE "bug|fix|error|crash|broken"; then
          log "    → Bug issue, label toevoegen..."
          gh issue edit "${org}/${repo}#$issue_num" --add-label "bug" 2>/dev/null && ((auto_handled++)) || true
        elif echo "$issue_title" | grep -qiE "feature|enhancement|add|new"; then
          log "    → Feature issue, label toevoegen..."
          gh issue edit "${org}/${repo}#$issue_num" --add-label "enhancement" 2>/dev/null && ((auto_handled++)) || true
        else
          log "    → Geen automatische actie"
          ((needs_attention++)) || true
        fi
      else
        log "    → Heeft al labels"
        ((needs_attention++)) || true
      fi
    done < <(echo "$local_issues" | jq -c '.[]' 2>/dev/null)
  fi
  
  # Haal open PRs op
  local_prs=$(gh pr list --repo "${org}/${repo}" --state open --json number,title,mergeable --limit 10 2>/dev/null || echo "[]")
  
  if [ "$local_prs" != "[]" ] && [ -n "$local_prs" ]; then
    while IFS= read -r pr; do
      [ -z "$pr" ] && continue
      total_items=$((total_items + 1))
      
      pr_num=$(echo "$pr" | jq -r '.number // "unknown"')
      pr_title=$(echo "$pr" | jq -r '.title // "unknown"')
      pr_mergeable=$(echo "$pr" | jq -r '.mergeable // "unknown"')
      
      log "  [$total_items] PR #$pr_num: $pr_title (mergeable: $pr_mergeable)"
      
      if [ "$pr_mergeable" = "MERGEABLE" ]; then
        log "    → PR is mergeable, review toevoegen..."
        gh pr review "${org}/${repo}#$pr_num" --approve --body "✅ Auto-approved by GitHub Fleet Manager" 2>/dev/null && ((auto_handled++)) || true
      else
        log "    → PR niet mergeable, aandacht nodig"
        ((needs_attention++)) || true
      fi
    done < <(echo "$local_prs" | jq -c '.[]' 2>/dev/null)
  fi
done

# Verwerk hmol33 repos
if [ -n "$HMOL33_TOKEN" ]; then
  log "  Verwerk hmol33 repos..."
  for repo in scripts Domo-Installer canal-digitaal OpenWebRx-Installer SoapyRemote-server-installer second-brain-app; do
    repo_dir="$REPOS_DIR/$repo"
    [ -d "$repo_dir/.git" ] || continue
    
    # Haal open issues op
    hmol33_issues=$(GITHUB_TOKEN="$HMOL33_TOKEN" gh issue list --repo "hmol33/$repo" --state open --json number,title,labels --limit 10 2>/dev/null || echo "[]")
    
    if [ "$hmol33_issues" != "[]" ] && [ -n "$hmol33_issues" ]; then
      while IFS= read -r issue; do
        [ -z "$issue" ] && continue
        total_items=$((total_items + 1))
        
        issue_num=$(echo "$issue" | jq -r '.number // "unknown"')
        issue_title=$(echo "$issue" | jq -r '.title // "unknown"')
        issue_labels=$(echo "$issue" | jq -r '.labels | length')
        
        log "  [$total_items] hmol33/$repo Issue #$issue_num: $issue_title (labels: $issue_labels)"
        
        if [ "$issue_labels" = "0" ]; then
          if echo "$issue_title" | grep -qiE "bug|fix|error|crash|broken"; then
            log "    → Bug issue, label toevoegen..."
            GITHUB_TOKEN="$HMOL33_TOKEN" gh issue edit "hmol33/$repo#$issue_num" --add-label "bug" 2>/dev/null && ((auto_handled++)) || true
          elif echo "$issue_title" | grep -qiE "feature|enhancement|add|new"; then
            log "    → Feature issue, label toevoegen..."
            GITHUB_TOKEN="$HMOL33_TOKEN" gh issue edit "hmol33/$repo#$issue_num" --add-label "enhancement" 2>/dev/null && ((auto_handled++)) || true
          else
            log "    → Geen automatische actie"
            ((needs_attention++)) || true
          fi
        else
          log "    → Heeft al labels"
          ((needs_attention++)) || true
        fi
      done < <(echo "$hmol33_issues" | jq -c '.[]' 2>/dev/null)
    fi
  done
fi

# Fase 3: Samenvatting
log "Fase 3: Samenvatting..."
log "  Totaal items: $total_items"
log "  Automatisch afgehandeld: $auto_handled"
log "  Nodig aandacht: $needs_attention"

log "=== GitHub Inbox Manager complete ==="
send_telegram_message "📬 *GitHub Inbox Manager*\n\n*Totaal:* $total_items\n*Automatisch:* $auto_handled\n*Aandacht nodig:* $needs_attention\n\n📋 Volledig log: $LOG_FILE" || true
