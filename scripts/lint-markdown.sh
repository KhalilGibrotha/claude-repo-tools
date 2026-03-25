#!/usr/bin/env bash
# lint-markdown.sh — Check markdown files for common LLM artifacts
#
# Usage:
#   lint-markdown.sh <repo-name>           # all .md files in repo
#   lint-markdown.sh <repo-name> <file>    # single file
#
# Checks:
#   - Smart/curly quotes
#   - Trailing backslashes
#   - Trailing whitespace (3+ spaces)
#   - Escaped underscores/asterisks in prose
#   - Manually numbered headings
#   - Non-breaking spaces (U+00A0)
#   - Mojibake patterns
#
# Exit codes: 0 = clean, 1 = issues found
#
# Performance: Uses a single Python pass per file to strip code blocks
# and YAML front matter, then runs grep checks on the filtered output.

source "$(dirname "$0")/../lib/common.sh"
require_tool git

if [[ $# -lt 1 ]]; then
    log_error "Usage: lint-markdown.sh <repo-name> [file]"
    exit 1
fi

resolve_repo "$1"
SINGLE_FILE="${2:-}"

# Collect files to check
if [[ -n "$SINGLE_FILE" ]]; then
    if [[ "$SINGLE_FILE" == /* ]]; then
        FILE_LIST="$SINGLE_FILE"
    else
        FILE_LIST="$REPO_PATH/$SINGLE_FILE"
    fi
else
    FILE_LIST=$(find "$REPO_PATH" \
        -name '*.md' \
        -not -name 'README.md' \
        -not -path '*/.git/*' \
        -not -path '*/node_modules/*' \
        2>/dev/null | sort)
fi

FILE_COUNT=$(echo "$FILE_LIST" | wc -l)
log_header "Linting $FILE_COUNT markdown files in $REPO_NAME"
echo ""

# Single Python script does all checks in one pass per file.
# This avoids the overhead of spawning grep per line.
$PYTHON -c "
import sys, re, os

checks = {
    'smart-quotes':      re.compile(r'[\u201c\u201d\u2018\u2019]'),
    'trailing-backslash': re.compile(r'\\\\$'),
    'trailing-whitespace': re.compile(r'   +$'),
    'escaped-char':      re.compile(r'(?<!\\\\)\\\\_|(?<!\\\\)\\\\\\*'),
    'numbered-heading':  re.compile(r'^#{1,3}\s+\d+\.\s'),
    'non-breaking-space': re.compile(r'\u00a0'),
    'mojibake':          re.compile(r'\xe2\x80[\x93\x94\x99\x9c\x9d]|â€'),
}

repo_path = sys.argv[1]
files = sys.argv[2:]
total_issues = 0

for filepath in files:
    if not os.path.isfile(filepath):
        continue
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
    except Exception:
        continue

    rel = os.path.relpath(filepath, repo_path)
    in_front = False
    in_code = False
    front_started = False

    for i, raw_line in enumerate(lines, 1):
        line = raw_line.rstrip('\n').rstrip('\r')

        # Track YAML front matter
        if i == 1 and line == '---':
            in_front = True
            front_started = True
            continue
        if in_front and line == '---':
            in_front = False
            continue
        if in_front:
            continue

        # Track fenced code blocks
        if line.startswith('\`\`\`'):
            in_code = not in_code
            continue
        if in_code:
            continue

        # Run all checks
        for name, pattern in checks.items():
            if pattern.search(line):
                # For escaped-char, strip inline code spans first
                if name == 'escaped-char':
                    stripped = re.sub(r'\`.+?\`', '', line)
                    if not pattern.search(stripped):
                        continue
                # For numbered-heading, skip if line is inside a blockquote or example
                if name == 'numbered-heading':
                    if '# 1. ' in line and ('not' in line.lower() or 'example' in line.lower() or '\`' in line):
                        continue
                print(f'  {rel}:{i}  [{name}]')
                print(f'    {line}')
                total_issues += 1

print()
if total_issues == 0:
    print('Clean — no issues found.')
    sys.exit(0)
else:
    print(f'{total_issues} issue(s) found.')
    sys.exit(1)
" "$REPO_PATH" $FILE_LIST
