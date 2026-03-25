#!/usr/bin/env bash
# release.sh — Create a release PR from working branch to default branch
#
# Usage:
#   release.sh <repo-name> ["Release message"]
#   release.sh <repo-name> ["Release message"] --merge
#
# Creates a PR from the working branch (develop) to the default branch
# (master/main). Optionally merges it immediately with --merge.

source "$(dirname "$0")/../lib/common.sh"
require_tool git
require_tool gh

if [[ $# -lt 1 ]]; then
    log_error "Usage: release.sh <repo-name> [\"message\"] [--merge]"
    exit 1
fi

REPO="$1"
shift

MESSAGE=""
DO_MERGE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --merge) DO_MERGE=true; shift ;;
        *) MESSAGE="$1"; shift ;;
    esac
done

resolve_repo "$REPO"

log_header "Release: $REPO_NAME ($REPO_WORKING_BRANCH → $REPO_DEFAULT_BRANCH)"

# ── Pre-flight checks ───────────────────────────────────────────────────────

# Fetch latest
git -C "$REPO_PATH" fetch origin 2>/dev/null

# Check working tree is clean
if ! is_clean "$REPO_PATH"; then
    log_error "Working tree has uncommitted changes. Commit or stash first."
    exit 1
fi

# Check working branch is up to date with origin
local_counts=$(ahead_behind "$REPO_PATH" "$REPO_WORKING_BRANCH" "origin/$REPO_WORKING_BRANCH")
local_ahead=$(echo "$local_counts" | awk '{print $1}')
if [[ "$local_ahead" != "0" ]]; then
    log_error "$REPO_WORKING_BRANCH has $local_ahead unpushed commits. Push first."
    exit 1
fi

# Check there is something to release
release_counts=$(ahead_behind "$REPO_PATH" "origin/$REPO_WORKING_BRANCH" "origin/$REPO_DEFAULT_BRANCH")
release_ahead=$(echo "$release_counts" | awk '{print $1}')
if [[ "$release_ahead" == "0" ]]; then
    log_info "Nothing to release — $REPO_WORKING_BRANCH and $REPO_DEFAULT_BRANCH are in sync."
    exit 0
fi

log_info "$release_ahead commits to release"

# ── Build PR content ────────────────────────────────────────────────────────

# Generate commit list
COMMIT_LIST=$(git -C "$REPO_PATH" log "origin/$REPO_DEFAULT_BRANCH..origin/$REPO_WORKING_BRANCH" --oneline)

# Generate diff stat
DIFF_STAT=$(git -C "$REPO_PATH" diff "origin/$REPO_DEFAULT_BRANCH...origin/$REPO_WORKING_BRANCH" --stat | tail -1)

# Auto-generate title if no message provided
if [[ -z "$MESSAGE" ]]; then
    MESSAGE="Release: $(echo "$COMMIT_LIST" | head -3 | paste -sd ', ' -)"
    # Truncate to 70 chars
    if [[ ${#MESSAGE} -gt 70 ]]; then
        MESSAGE="${MESSAGE:0:67}..."
    fi
fi

PR_TITLE="$MESSAGE"

PR_BODY="## Summary

$DIFF_STAT

## Commits

\`\`\`
$COMMIT_LIST
\`\`\`

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)"

# ── Create PR ────────────────────────────────────────────────────────────────

log_info "Creating PR..."
PR_URL=$(gh pr create \
    --repo "$REPO_SLUG" \
    --base "$REPO_DEFAULT_BRANCH" \
    --head "$REPO_WORKING_BRANCH" \
    --title "$PR_TITLE" \
    --body "$PR_BODY" 2>&1)

log_info "PR created: $PR_URL"

# ── Optional merge ───────────────────────────────────────────────────────────

if [[ "$DO_MERGE" == true ]]; then
    log_info "Merging..."
    gh pr merge --repo "$REPO_SLUG" --merge "$PR_URL" 2>&1
    log_info "Merged."

    # Sync local
    git -C "$REPO_PATH" pull origin "$REPO_DEFAULT_BRANCH" 2>/dev/null
    log_info "Local $REPO_DEFAULT_BRANCH synced."
fi
