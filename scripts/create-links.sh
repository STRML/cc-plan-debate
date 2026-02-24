#!/bin/bash
# create-links.sh — create a stable symlink at ~/.claude/debate-scripts
# pointing to this scripts directory.
# Run once after install or update via /debate:setup.

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
LINK="$HOME/.claude/debate-scripts"

ln -sfn "$SELF_DIR" "$LINK"
echo "✅ Symlink created: $LINK -> $SELF_DIR"
echo "   Re-run /debate:setup after updating the plugin to refresh this link."
