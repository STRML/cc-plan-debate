#!/bin/bash
# debate-setup.sh — initialize a review session.
# Generates REVIEW_ID, creates the temp working directory, and outputs the
# scripts directory so callers can use literal paths for invoke scripts.
#
# Usage: debate-setup.sh
#
# Output (stdout, key=value):
#   REVIEW_ID=<8-char hex>
#   WORK_DIR=/tmp/claude/ai-review-<REVIEW_ID>
#   SCRIPT_DIR=<stable symlink ~/.claude/debate-scripts, or this script's own dir>

REVIEW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | head -c 8)
WORK_DIR="/tmp/claude/ai-review-${REVIEW_ID}"

mkdir -p "$WORK_DIR" || { echo "ERROR: failed to create $WORK_DIR" >&2; exit 1; }

echo "REVIEW_ID=${REVIEW_ID}"
echo "WORK_DIR=${WORK_DIR}"

# Prefer the stable symlink so subsequent Claude Bash tool calls use a path
# that matches the allowed-tools patterns in each command file.
STABLE_LINK="$HOME/.claude/debate-scripts"
if [ -d "$STABLE_LINK" ]; then
  echo "SCRIPT_DIR=${STABLE_LINK}"
else
  SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
  echo "SCRIPT_DIR=${SELF_DIR}"
fi
