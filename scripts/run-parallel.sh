#!/bin/bash
# Static parallel runner for debate plugin — executed by /debate:all
# Usage: run-parallel.sh <REVIEW_ID> <TIMEOUT_BIN>
#   REVIEW_ID   — 8-char hex ID used for all temp file paths
#   TIMEOUT_BIN — path to timeout binary (optional; empty = no timeout)

REVIEW_ID="$1"
TIMEOUT_BIN="$2"

if [ -z "$REVIEW_ID" ]; then
  echo "Usage: $0 <REVIEW_ID> [TIMEOUT_BIN]" >&2
  exit 1
fi

WORK_DIR="/tmp/claude/ai-review-${REVIEW_ID}"

mkdir -p "$WORK_DIR" || { echo "Failed to create $WORK_DIR" >&2; exit 1; }

# Clear any leftover *-prompt.txt files from a prior debate phase so they
# don't bleed into this fresh parallel review round.
rm -f "$WORK_DIR"/codex-prompt.txt "$WORK_DIR"/gemini-prompt.txt "$WORK_DIR"/opus-prompt.txt

# Timeouts are managed per-reviewer inside each invoke-*.sh script:
# Codex/Gemini: 120s, Opus: 300s (claude CLI startup adds overhead).
# TIMEOUT_BIN is passed via env to each subshell.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDS=()

if command -v codex > /dev/null 2>&1; then
  (
    TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-codex.sh" "$WORK_DIR"
  ) &
  PIDS+=($!)
fi

if command -v gemini > /dev/null 2>&1; then
  (
    TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-gemini.sh" "$WORK_DIR"
  ) &
  PIDS+=($!)
fi

if command -v claude > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
  (
    TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-opus.sh" "$WORK_DIR"
  ) &
  PIDS+=($!)
fi

if [ ${#PIDS[@]} -gt 0 ]; then
  wait "${PIDS[@]}"
fi
echo "All reviewers complete"
