#!/usr/bin/env bash
# Multi-account support voor fleet-manager

ACCOUNTS=("itsdarklikehell" "hmol33")

get_account_token() {
    local account="$1"
    case "$account" in
        itsdarklikehell) echo "${GITHUB_TOKEN:-}" ;;
        hmol33) echo "${GH_TOKEN_HMOL33:-}" ;;
        *) echo "" ;;
    esac
}

get_account_repos() {
    local account="$1"
    local token
    token=$(get_account_token "$account")
    GH_TOKEN="$token" gh repo list "$account" --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || echo ""
}
