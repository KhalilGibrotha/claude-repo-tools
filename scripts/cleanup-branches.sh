#!/usr/bin/env bash
# cleanup-branches.sh — Delete merged local and remote feature branches
#
# Usage:
#   cleanup-branches.sh <repo-name>             # delete merged branches
#   cleanup-branches.sh <repo-name> --dry-run   # show what would be deleted
#   cleanup-branches.sh                          # all repos, dry-run

source "$(dirname "$0")/../lib/common.sh"
require_tool git
require_tool gh

DRY_RUN=false
REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        *) REPO="$1"; shift ;;
    esac
done

cleanup_one_repo() {
    local name="$1"
    resolve_repo "$name"

    log_header "Cleanup: $REPO_NAME"

    # Prune stale remote refs
    git -C "$REPO_PATH" fetch --prune origin 2>/dev/null

    local deleted=0

    # Find local branches merged into default branch
    local merged_branches
    merged_branches=$(git -C "$REPO_PATH" branch --merged "origin/$REPO_DEFAULT_BRANCH" 2>/dev/null \
        | grep -v "^\*" \
        | grep -v "^\s*${REPO_DEFAULT_BRANCH}$" \
        | grep -v "^\s*${REPO_WORKING_BRANCH}$" \
        | sed 's/^[ *]*//' \
        || true)

    # Also find orphaned branches (remote gone)
    local orphaned_branches
    orphaned_branches=$(git -C "$REPO_PATH" branch -vv 2>/dev/null \
        | grep '\[.*: gone\]' \
        | sed 's/^[ *]*//' \
        | awk '{print $1}' \
        || true)

    # Combine and deduplicate
    local all_candidates
    all_candidates=$(echo -e "${merged_branches}\n${orphaned_branches}" | sort -u | grep -v '^\s*$' || true)

    if [[ -z "$all_candidates" ]]; then
        log_info "No branches to clean up."
        echo ""
        return
    fi

    echo "$all_candidates" | while read -r branch; do
        [[ -z "$branch" ]] && continue

        # Check if remote branch still exists
        local has_remote=false
        if git -C "$REPO_PATH" ls-remote --heads origin "$branch" 2>/dev/null | grep -q "$branch"; then
            has_remote=true
        fi

        if [[ "$DRY_RUN" == true ]]; then
            if [[ "$has_remote" == true ]]; then
                log_info "[dry-run] Would delete: $branch (local + remote)"
            else
                log_info "[dry-run] Would delete: $branch (local only)"
            fi
        else
            # Delete remote if it exists
            if [[ "$has_remote" == true ]]; then
                git -C "$REPO_PATH" push origin --delete "$branch" 2>/dev/null && \
                    log_info "Deleted remote: origin/$branch" || \
                    log_warn "Failed to delete remote: origin/$branch"
            fi

            # Delete local — use -D for orphaned branches (remote gone, PR merged
            # on GitHub via squash/merge which doesn't register as merged locally)
            if [[ "$has_remote" == false ]]; then
                git -C "$REPO_PATH" branch -D "$branch" 2>/dev/null && \
                    log_info "Deleted local: $branch (orphaned)" || \
                    log_warn "Failed to delete local: $branch"
            else
                git -C "$REPO_PATH" branch -d "$branch" 2>/dev/null && \
                    log_info "Deleted local: $branch" || \
                    log_warn "Failed to delete local: $branch (may not be fully merged)"
            fi

            deleted=$((deleted + 1))
        fi
    done

    echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────

if [[ -n "$REPO" ]]; then
    cleanup_one_repo "$REPO"
else
    DRY_RUN=true
    log_warn "No repo specified — running all repos in dry-run mode"
    echo ""
    for repo in $(list_repos); do
        cleanup_one_repo "$repo"
    done
fi
