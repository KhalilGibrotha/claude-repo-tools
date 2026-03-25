# Claude Repo Tools — Claude Instructions

Shell scripts used by Claude Code for cross-repo management, validation, and release automation. These scripts operate on registered repos defined in `config/repos.conf`.

## Repo Structure

- `scripts/` — Executable scripts (check-status, release, cleanup, verify-docx)
- `lib/common.sh` — Shared functions (repo resolution, logging, git helpers)
- `config/repos.conf` — Repo registry: maps names to local paths, branch conventions, and GitHub slugs

## Script Interfaces

### `check-status.sh [repo-name]`
Cross-repo health check. Run with no args for all repos. Reports: current branch, ahead/behind counts, open PRs, stale branches, orphaned branches.

### `release.sh <repo-name> ["message"] [--merge]`
Creates a release PR from working branch → default branch. Pre-flight checks: clean tree, no unpushed commits, something to release. `--merge` also merges and syncs local.

### `cleanup-branches.sh <repo-name> [--dry-run]`
Deletes local and remote branches that are merged into the default branch. No args = all repos in dry-run mode. Excludes the working and default branches.

### `verify-docx.sh <path-to-markdown-file>`
Builds a DOCX and prints the heading tree. Finds `vars/org.yaml` by walking up from the file. Uses conda Python for inspection.

## Key Conventions

- `$PYTHON` defaults to `python` — set to your conda/venv Python path if python-docx is not on the default Python
- Scripts assume Git Bash on Windows (MSYS2 path conventions)
- `gh` CLI must be authenticated
- All path variables are double-quoted to handle OneDrive spaces
- Scripts use `set -euo pipefail`

## Adding a Repo

Add a line to `config/repos.conf`:
```
name | /absolute/local/path | default_branch | working_branch | Owner/repo-name
```

## Editing Scripts

- Source `lib/common.sh` in every new script
- Use `resolve_repo` for path/branch lookup — never hardcode
- Use `log_info`, `log_warn`, `log_error` for output
- Test with `--dry-run` where applicable before live runs
