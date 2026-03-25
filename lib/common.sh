#!/usr/bin/env bash
# common.sh — Shared functions for claude-repo-tools scripts
# Source this file: source "$(dirname "$0")/../lib/common.sh"

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────

TOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_CONF="$TOOLS_ROOT/config/repos.conf"
PYTHON="${PYTHON:-/c/Users/alexg/miniconda3/python}"

# ── Logging ──────────────────────────────────────────────────────────────────

log_info()  { echo "  $*"; }
log_warn()  { echo "  WARN: $*" >&2; }
log_error() { echo "  ERROR: $*" >&2; }
log_header() { echo "=== $* ==="; }

# ── Repo Registry ───────────────────────────────────────────────────────────

# resolve_repo <name>
# Sets: REPO_NAME, REPO_PATH, REPO_DEFAULT_BRANCH, REPO_WORKING_BRANCH, REPO_SLUG
resolve_repo() {
    local name="$1"
    local line
    line=$(grep -v '^\s*#' "$REPOS_CONF" | grep -v '^\s*$' | grep "^${name}\s*|" | head -1)

    if [[ -z "$line" ]]; then
        log_error "Repo '$name' not found in $REPOS_CONF"
        return 1
    fi

    REPO_NAME="$(echo "$line" | cut -d'|' -f1 | xargs)"
    REPO_PATH="$(echo "$line" | cut -d'|' -f2 | xargs)"
    REPO_DEFAULT_BRANCH="$(echo "$line" | cut -d'|' -f3 | xargs)"
    REPO_WORKING_BRANCH="$(echo "$line" | cut -d'|' -f4 | xargs)"
    REPO_SLUG="$(echo "$line" | cut -d'|' -f5 | xargs)"

    if [[ ! -d "$REPO_PATH/.git" ]]; then
        log_error "Repo path '$REPO_PATH' is not a git repository"
        return 1
    fi
}

# list_repos — prints all repo names from the registry
list_repos() {
    grep -v '^\s*#' "$REPOS_CONF" | grep -v '^\s*$' | cut -d'|' -f1 | xargs -I{} echo {}
}

# ── Git Helpers ──────────────────────────────────────────────────────────────

# ahead_behind <path> <local_ref> <remote_ref>
# Prints "ahead behind" counts (e.g. "3 0")
ahead_behind() {
    local repo_path="$1" local_ref="$2" remote_ref="$3"
    git -C "$repo_path" rev-list --left-right --count "${local_ref}...${remote_ref}" 2>/dev/null || echo "0 0"
}

# current_branch <path>
current_branch() {
    git -C "$1" branch --show-current 2>/dev/null || echo "(detached)"
}

# is_clean <path> — returns 0 if working tree is clean
is_clean() {
    git -C "$1" diff --quiet && git -C "$1" diff --cached --quiet
}

# ── Tool Checks ──────────────────────────────────────────────────────────────

require_tool() {
    if ! command -v "$1" &>/dev/null; then
        log_error "Required tool '$1' not found in PATH"
        return 1
    fi
}
