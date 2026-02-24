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

# Source config.env if present — provides CODEX_MODEL, GEMINI_MODEL, OPUS_MODEL overrides
# written by the caller before invoking this script.
[ -f "$WORK_DIR/config.env" ] && source "$WORK_DIR/config.env"
CODEX_MODEL="${CODEX_MODEL:-gpt-4.1}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-pro}"
OPUS_MODEL="${OPUS_MODEL:-claude-opus-4-6}"

# Timeouts are managed per-reviewer inside each invoke-*.sh script:
# Codex: 120s, Gemini: 240s, Opus: 300s (claude CLI startup adds overhead).
# TIMEOUT_BIN is passed as env to each subshell; invoke scripts also self-detect it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDS=()

if command -v codex > /dev/null 2>&1; then
  (
    TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-codex.sh" "$WORK_DIR" "" "$CODEX_MODEL"
  ) &
  PIDS+=($!)
fi

if command -v gemini > /dev/null 2>&1; then
  (
    TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-gemini.sh" "$WORK_DIR" "" "$GEMINI_MODEL"
  ) &
  PIDS+=($!)
fi

if command -v claude > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
  (
    TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-opus.sh" "$WORK_DIR" "" "$OPUS_MODEL"
  ) &
  PIDS+=($!)
fi

if [ ${#PIDS[@]} -gt 0 ]; then
  wait "${PIDS[@]}"
fi
echo "All reviewers complete"
