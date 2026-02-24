#!/bin/bash
# Static parallel runner for debate plugin — executed by /debate:all
# Usage: run-parallel.sh <REVIEW_ID>
#   REVIEW_ID — 8-char hex ID used for all temp file paths
#
# Reviewers are spawned with nohup + disown so they survive if the parent
# shell is killed (e.g. Bash tool exit 144). Exit codes are polled via
# *-exit.txt files written by each invoke-*.sh script.

REVIEW_ID="$1"

if [ -z "$REVIEW_ID" ]; then
  echo "Usage: $0 <REVIEW_ID>" >&2
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
CODEX_MODEL="${CODEX_MODEL:-gpt-5.3-codex}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.1-pro-preview}"
OPUS_MODEL="${OPUS_MODEL:-claude-opus-4-6}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Track which exit files to wait for
EXIT_FILES=()

if command -v codex > /dev/null 2>&1; then
  echo "[debate] Spawning codex (${CODEX_MODEL})..." >&2
  rm -f "$WORK_DIR/codex-exit.txt"
  nohup bash "$SCRIPT_DIR/invoke-codex.sh" "$WORK_DIR" "" "$CODEX_MODEL" > /dev/null 2>&1 &
  CODEX_PID=$!
  disown $CODEX_PID
  EXIT_FILES+=("$WORK_DIR/codex-exit.txt")
fi

if command -v gemini > /dev/null 2>&1; then
  echo "[debate] Spawning gemini (${GEMINI_MODEL})..." >&2
  rm -f "$WORK_DIR/gemini-exit.txt"
  nohup bash "$SCRIPT_DIR/invoke-gemini.sh" "$WORK_DIR" "" "$GEMINI_MODEL" > /dev/null 2>&1 &
  GEMINI_PID=$!
  disown $GEMINI_PID
  EXIT_FILES+=("$WORK_DIR/gemini-exit.txt")
fi

if command -v claude > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
  echo "[debate] Spawning opus (${OPUS_MODEL})..." >&2
  rm -f "$WORK_DIR/opus-exit.txt"
  nohup bash "$SCRIPT_DIR/invoke-opus.sh" "$WORK_DIR" "" "$OPUS_MODEL" > /dev/null 2>&1 &
  OPUS_PID=$!
  disown $OPUS_PID
  EXIT_FILES+=("$WORK_DIR/opus-exit.txt")
fi

if [ ${#EXIT_FILES[@]} -eq 0 ]; then
  echo "[debate] No reviewers available." >&2
  exit 1
fi

echo "[debate] Waiting for ${#EXIT_FILES[@]} reviewer(s)..." >&2

# Poll for exit files. Each invoke-*.sh writes an exit code to *-exit.txt when done.
# Polling allows this script to detect completion even after a parent-kill / restart.
POLL_INTERVAL=2
ELAPSED=0
MAX_WAIT="${POLL_MAX_WAIT:-450}"  # longer than max opus timeout (300s) + buffer

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  DONE=0
  for f in "${EXIT_FILES[@]}"; do
    [ -f "$f" ] && DONE=$((DONE + 1))
  done
  if [ "$DONE" -ge "${#EXIT_FILES[@]}" ]; then
    break
  fi
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

echo "[debate] All reviewers complete." >&2
