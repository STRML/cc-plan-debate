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

# Timeouts are managed per-reviewer inside each invoke-*.sh script:
# Codex/Gemini: 120s, Opus: 300s (claude CLI startup adds overhead).
# TIMEOUT_BIN is passed via env to each subshell.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDS=()

if which codex > /dev/null 2>&1; then
  (
    TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-codex.sh" "$WORK_DIR"
  ) &
  PIDS+=($!)
fi

if which gemini > /dev/null 2>&1; then
  (
    TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-gemini.sh" "$WORK_DIR"
  ) &
  PIDS+=($!)
fi

if which claude > /dev/null 2>&1 && which jq > /dev/null 2>&1; then
  (
    TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-opus.sh" "$WORK_DIR"
  ) &
  PIDS+=($!)
fi

if [ ${#PIDS[@]} -gt 0 ]; then
  wait "${PIDS[@]}"
fi
echo "All reviewers complete"
