#!/bin/bash
# create-links.sh — create a stable symlink at ~/.claude/debate-scripts
# pointing to this scripts directory.
# Run once after install or update via /debate:setup.

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
LINK="$HOME/.claude/debate-scripts"

if ln -sfn "$SELF_DIR" "$LINK" 2>/dev/null; then
  echo "✅ Symlink created: $LINK -> $SELF_DIR"
  echo "   Re-run /debate:setup after updating the plugin to refresh this link."
else
  echo "⚠️  Sandbox blocked symlink creation (ln -sfn is restricted to project dir)."
  echo ""
  echo "   Run this once from your regular terminal (outside Claude Code):"
  echo ""
  echo "   ln -sfn \"$SELF_DIR\" \"$LINK\""
  echo ""
  echo "   Or add to ~/.claude/settings.json:"
  echo "     \"sandbox\": { \"allowedPaths\": [\"$LINK\"] }"
  exit 1
fi
