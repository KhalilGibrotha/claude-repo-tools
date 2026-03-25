#!/usr/bin/env bash
# verify-docx.sh — Build a DOCX from markdown and print the heading tree
#
# Usage:
#   verify-docx.sh <path-to-markdown-file>
#
# Builds the document using docx-build, then inspects the resulting
# DOCX with python-docx to print the heading hierarchy. Useful for
# verifying that section numbering is correct after rendering changes.

source "$(dirname "$0")/../lib/common.sh"
require_tool docx-build

if [[ $# -lt 1 ]]; then
    log_error "Usage: verify-docx.sh <path-to-markdown-file>"
    exit 1
fi

MD_FILE="$1"

if [[ ! -f "$MD_FILE" ]]; then
    log_error "File not found: $MD_FILE"
    exit 1
fi

# Resolve absolute path
MD_FILE="$(cd "$(dirname "$MD_FILE")" && pwd)/$(basename "$MD_FILE")"

# Find the content repo root (walk up looking for vars/org.yaml)
find_repo_root() {
    local dir="$1"
    while [[ "$dir" != "/" && "$dir" != "." ]]; do
        if [[ -f "$dir/vars/org.yaml" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

REPO_ROOT=$(find_repo_root "$(dirname "$MD_FILE")") || {
    log_warn "No vars/org.yaml found — building without org identity"
    REPO_ROOT=""
}

# Build the DOCX
BASENAME=$(basename "$MD_FILE" .md)
OUT_FILE="/tmp/verify_${BASENAME}.docx"

log_header "Building: $(basename "$MD_FILE")"

ORG_ARGS=()
if [[ -n "$REPO_ROOT" && -f "$REPO_ROOT/vars/org.yaml" ]]; then
    ORG_ARGS=(--org "$REPO_ROOT/vars/org.yaml")
fi

docx-build "$MD_FILE" "${ORG_ARGS[@]}" --output "$OUT_FILE" 2>&1

if [[ ! -f "$OUT_FILE" ]]; then
    log_error "Build failed — no output file"
    exit 1
fi

# Inspect heading tree
log_header "Heading Tree"

"$PYTHON" -c "
import sys
from docx import Document

doc = Document(sys.argv[1])
for p in doc.paragraphs:
    if p.style.name.startswith('Heading'):
        level = int(p.style.name.split()[-1])
        indent = '  ' * (level - 1)
        print(f'{indent}H{level}: {p.text}')
" "$OUT_FILE"

echo ""
log_info "DOCX: $OUT_FILE"
