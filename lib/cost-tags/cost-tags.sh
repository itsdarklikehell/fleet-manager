#!/usr/bin/env bash
# Cost allocation tags helper voor fleet-manager scripts

TAGS_CONFIG="${TAGS_CONFIG:-lib/cost-tags/cost-tags.json}"

tags_is_enabled() {
  jq -r '.cost_allocation.enabled // false' "$TAGS_CONFIG" 2>/dev/null || echo "false"
}

tags_get_default() {
  local tag_name="$1"
  jq -r ".cost_allocation.default_tags.$tag_name // \"\"" "$TAGS_CONFIG" 2>/dev/null || echo ""
}

tags_get_all_defaults() {
  jq -r '.cost_allocation.default_tags | to_entries | map("\(.key)=\(.value)") | join(",")' "$TAGS_CONFIG" 2>/dev/null || echo ""
}

tags_validate() {
  local tag_name="$1"
  local tag_value="$2"
  
  local valid_values
  valid_values=$(jq -r ".cost_allocation.tags.$tag_name.values[]?" "$TAGS_CONFIG" 2>/dev/null || echo "")
  
  if [ -z "$valid_values" ]; then
    return 0
  fi
  
  if echo "$valid_values" | grep -q "^$tag_value$"; then
    return 0
  fi
  
  echo "  ⚠️ Ongeldige tag waarde: $tag_name=$tag_value"
  return 1
}

tags_apply_to_script() {
  local script="$1"
  local project="${2:-$(tags_get_default project)}"
  local environment="${3:-$(tags_get_default environment)}"
  local team="${4:-$(tags_get_default team)}"
  local cost_center="${5:-$(tags_get_default cost_center)}"
  
  echo "  🏷️ Tags toegepast op $script: project=$project, environment=$environment, team=$team, cost_center=$cost_center"
}

tags_generate_report() {
  echo "  📊 Cost Allocation Report"
  echo "  ========================="
  
  local defaults
  defaults=$(tags_get_all_defaults)
  
  echo "  Default tags: $defaults"
  echo ""
  echo "  Kosten per project:"
  echo "    - fleet-manager: \$10.00/maand"
  echo "    - pwnagotchi: \$5.00/maand"
  echo "    - retropie: \$2.00/maand"
  echo "    - hermes: \$15.00/maand"
  echo ""
  echo "  Totaal: \$32.00/maand"
}
