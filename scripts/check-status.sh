#!/usr/bin/env bash
# check-status.sh — Cross-repo health check
#
# Usage:
#   check-status.sh                 # all registered repos
#   check-status.sh architecture-docs  # one repo
#
# Reports: current branch, ahead/behind, open PRs, stale branches

source "$(dirname "$0")/../lib/common.sh"
require_tool git
require_tool gh

check_one_repo() {
    local name="$1"
    resolve_repo "$name"

    log_header "$REPO_NAME ($REPO_SLUG)"

    # Fetch silently
    git -C "$REPO_PATH" fetch --prune origin 2>/dev/null

    # Current branch
    local branch
    branch=$(current_branch "$REPO_PATH")
    log_info "Branch: $branch"

    # Working branch ahead/behind origin
    local counts
    counts=$(ahead_behind "$REPO_PATH" "$REPO_WORKING_BRANCH" "origin/$REPO_WORKING_BRANCH")
    local ahead behind
    ahead=$(echo "$counts" | awk '{print $1}')
    behind=$(echo "$counts" | awk '{print $2}')
    if [[ "$ahead" != "0" || "$behind" != "0" ]]; then
        log_info "$REPO_WORKING_BRANCH: ${ahead} ahead, ${behind} behind origin"
    else
        log_info "$REPO_WORKING_BRANCH: up to date with origin"
    fi

    # Working branch vs default branch
    counts=$(ahead_behind "$REPO_PATH" "origin/$REPO_WORKING_BRANCH" "origin/$REPO_DEFAULT_BRANCH")
    ahead=$(echo "$counts" | awk '{print $1}')
    behind=$(echo "$counts" | awk '{print $2}')
    if [[ "$ahead" != "0" ]]; then
        log_info "$REPO_WORKING_BRANCH → $REPO_DEFAULT_BRANCH: ${ahead} commits to release"
    else
        log_info "$REPO_WORKING_BRANCH = $REPO_DEFAULT_BRANCH (in sync)"
    fi

    # Working tree status
    if is_clean "$REPO_PATH"; then
        log_info "Working tree: clean"
    else
        log_warn "Working tree: uncommitted changes"
    fi

    # Open PRs
    local pr_count
    pr_count=$(gh pr list --repo "$REPO_SLUG" --state open --json number --jq 'length' 2>/dev/null || echo "?")
    if [[ "$pr_count" == "0" ]]; then
        log_info "Open PRs: none"
    else
        log_info "Open PRs: $pr_count"
        gh pr list --repo "$REPO_SLUG" --state open --json number,title,headRefName \
            --jq '.[] | "    #\(.number) \(.headRefName) — \(.title)"' 2>/dev/null || true
    fi

    # Stale local branches (merged into default but not deleted)
    local stale_branches
    stale_branches=$(git -C "$REPO_PATH" branch --merged "origin/$REPO_DEFAULT_BRANCH" 2>/dev/null \
        | grep -v "^\*" \
        | grep -v "^\s*${REPO_DEFAULT_BRANCH}$" \
        | grep -v "^\s*${REPO_WORKING_BRANCH}$" \
        | sed 's/^[ *]*//' \
        || true)

    if [[ -n "$stale_branches" ]]; then
        log_warn "Stale local branches (merged into $REPO_DEFAULT_BRANCH):"
        echo "$stale_branches" | while read -r b; do
            echo "    $b"
        done
    fi

    # Orphaned local branches (remote gone)
    local orphaned
    orphaned=$(git -C "$REPO_PATH" branch -vv 2>/dev/null \
        | grep '\[.*: gone\]' \
        | sed 's/^[ *]*//' \
        | awk '{print $1}' \
        || true)

    if [[ -n "$orphaned" ]]; then
        log_warn "Orphaned branches (remote deleted):"
        echo "$orphaned" | while read -r b; do
            echo "    $b"
        done
    fi

    echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────

if [[ $# -gt 0 ]]; then
    check_one_repo "$1"
else
    for repo in $(list_repos); do
        check_one_repo "$repo"
    done
fi
