# claude-repo-tools

Shell scripts used by [Claude Code](https://claude.com/claude-code) for cross-repo management, validation, and release automation.

## What This Is

When Claude Code works across multiple repositories in a session — checking PR status, creating release PRs, cleaning up branches, verifying DOCX rendering — the same multi-step command sequences repeat. These scripts consolidate those patterns into reusable tools.

The scripts are designed to be invoked by Claude Code during sessions but are human-readable and usable from the terminal.

## Scripts

| Script | Purpose |
|---|---|
| `check-status.sh` | Cross-repo health check: branches, PRs, drift |
| `release.sh` | Create and optionally merge a release PR |
| `cleanup-branches.sh` | Delete merged local and remote feature branches |
| `verify-docx.sh` | Build a DOCX and print the heading tree |

## Configuration

Repos are registered in `config/repos.conf` — a simple pipe-delimited file mapping repo names to local paths, branch conventions, and GitHub slugs.

## Requirements

- Git Bash (Windows) or Bash 4+
- `gh` CLI authenticated with GitHub
- `docx-build` on PATH (for `verify-docx.sh`)
- Python with `python-docx` installed (for `verify-docx.sh`)

## License

MIT
