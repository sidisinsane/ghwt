#!/usr/bin/env bash
# install.sh
#
# Creates the bin/ghwt symlink on first run. Safe to run multiple times.
# Sourced automatically by generate.sh — can also be run directly.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SYMLINK="$REPO_DIR/bin/ghwt"

if [ ! -L "$SYMLINK" ]; then
    ln -s "$REPO_DIR/generate.sh" "$SYMLINK"
    echo "✓ Created $SYMLINK" >&2
    echo "  Add $REPO_DIR/bin to your PATH to use ghwt from anywhere." >&2
fi
