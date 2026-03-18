#!/bin/bash
# Generic reviewer invocation via acpx CLI.
# Replaces invoke-codex.sh, invoke-gemini.sh, invoke-opus.sh, invoke-openai-compat.sh.
#
# Usage: invoke-acpx.sh <config_file> <work_dir> <reviewer_name> [timeout]
#   config_file   — path to JSON config (e.g. ~/.claude/debate-acpx.json)
#   work_dir      — temp directory (must contain plan.md)
#   reviewer_name — e.g. "codex", "gemini", "kimi"
#   timeout       — optional override; falls back to config value, then 120s
#
# Config schema:
#   {
#     "reviewers": {
#       "<name>": {
#         "agent": "codex",
#         "timeout": 120,
#         "system_prompt": "You are The Executor..."
#       }
#     }
#   }
#
# Prompt resolution (in order):
#   1. $work_dir/<name>-prompt.txt  (debate/revision rounds write this)
#   2. reviewers.<name>.system_prompt from config + plan.md
#   3. Built-in fallback: generic plan reviewer + plan.md
#
# Output files (all written to $work_dir):
#   <name>-output.md   review text
#   <name>-stderr.log  acpx stderr (for debugging)
#   <name>-exit.txt    exit code (0=success, 124=timeout, 1=error)

set -euo pipefail

CONFIG_FILE="${1:-}"
WORK_DIR="${2:-}"
REVIEWER="${3:-}"
TIMEOUT_ARG="${4:-}"

if [ -z "$CONFIG_FILE" ] || [ -z "$WORK_DIR" ] || [ -z "$REVIEWER" ]; then
  echo "Usage: $0 <config_file> <work_dir> <reviewer_name> [timeout]" >&2
  exit 1
fi

# --- Resolve acpx binary (support npx fallback) ---

ACPX_BIN=()
if command -v acpx > /dev/null 2>&1; then
  ACPX_BIN=(acpx)
elif command -v npx > /dev/null 2>&1; then
  ACPX_BIN=(npx acpx@latest)
else
  echo "invoke-acpx: acpx not found. Install: npm install -g acpx@latest" >&2
  # Write a meaningful exit file if we can
  if [ -n "$WORK_DIR" ] && [ -n "$REVIEWER" ] && [ -d "$WORK_DIR" ]; then
    echo "1" > "$WORK_DIR/${REVIEWER}-exit.txt"
    echo "acpx not installed. Run: npm install -g acpx@latest" > "$WORK_DIR/${REVIEWER}-output.md"
  fi
  exit 1
fi

# --- Trap: ensure exit file is always written on unexpected exit ---
# Only fires on abnormal termination — normal exit paths call trap - EXIT before returning.

create_exit_file() {
  local code="${1:-1}"
  if [ -n "$WORK_DIR" ] && [ -n "$REVIEWER" ]; then
    echo "$code" > "$WORK_DIR/${REVIEWER}-exit.txt"
    if [ ! -f "$WORK_DIR/${REVIEWER}-output.md" ]; then
      echo "invoke-acpx: process terminated unexpectedly (exit $code)" > "$WORK_DIR/${REVIEWER}-output.md"
    fi
  fi
}

trap 'create_exit_file "$?"' EXIT

if [ ! -d "$WORK_DIR" ]; then
  echo "invoke-acpx: work_dir does not exist: $WORK_DIR" >&2
  exit 1
fi

if [ ! -f "$WORK_DIR/plan.md" ]; then
  echo "invoke-acpx: plan.md not found in $WORK_DIR" >&2
  exit 1
fi

if [ ! -s "$WORK_DIR/plan.md" ]; then
  echo "invoke-acpx: plan.md is empty in $WORK_DIR" >&2
  exit 1
fi

# --- Config ---

if [ ! -f "$CONFIG_FILE" ]; then
  echo "invoke-acpx: config not found: $CONFIG_FILE" >&2
  exit 1
fi

AGENT=$(jq -r --arg rev "$REVIEWER" '.reviewers[$rev].agent // empty' "$CONFIG_FILE")
if [ -z "$AGENT" ]; then
  echo "invoke-acpx: no agent for '$REVIEWER' in $CONFIG_FILE" >&2
  exit 1
fi

CONFIG_TIMEOUT=$(jq -r --arg rev "$REVIEWER" '.reviewers[$rev].timeout // empty' "$CONFIG_FILE")
CONFIG_SYSTEM_PROMPT=$(jq -r --arg rev "$REVIEWER" '.reviewers[$rev].system_prompt // empty' "$CONFIG_FILE")

# --- Session creation: always create a session before running ---
# acpx requires a session to exist. `sessions list` returns exit 0 with empty
# output when no sessions exist, so we can't use it to detect the "no sessions"
# case reliably. Instead, always call `sessions new` — it's idempotent enough
# for our purposes and guarantees a valid session before each run.
# Skip if SKIP_SESSION_CHECK is set (for testing with mock acpx)

if [ -z "${SKIP_SESSION_CHECK:-}" ]; then
  echo "[$REVIEWER] Creating acpx session for '$AGENT'..." >&2
  if ! "${ACPX_BIN[@]}" "$AGENT" sessions new > /dev/null 2>&1; then
    echo "[$REVIEWER] Failed to create acpx session for '$AGENT'." >&2
    echo "  Check that the agent CLI is installed and authenticated." >&2
    echo "  Run /debate:acpx-setup to diagnose." >&2
    echo "4" > "$WORK_DIR/${REVIEWER}-exit.txt"
    echo "Failed to create acpx session for '$AGENT'. Run /debate:acpx-setup to diagnose." > "$WORK_DIR/${REVIEWER}-output.md"
    trap - EXIT
    exit 4
  fi
  echo "[$REVIEWER] Session ready." >&2
fi

TIMEOUT="${TIMEOUT_ARG:-${CONFIG_TIMEOUT:-120}}"
if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -le 0 ]; then
  echo "invoke-acpx: invalid timeout '$TIMEOUT' for '$REVIEWER', using 120s" >&2
  TIMEOUT=120
fi

# --- Prompt ---

PROMPT_FILE=""

if [ -f "$WORK_DIR/${REVIEWER}-prompt.txt" ]; then
  # Debate/revision round — prompt file is the full message
  PROMPT_FILE="$WORK_DIR/${REVIEWER}-prompt.txt"
else
  # Initial review — build prompt from system_prompt + plan
  SYSTEM_PROMPT="${CONFIG_SYSTEM_PROMPT:-You are a senior engineer reviewing an implementation plan. Be specific, direct, and focus on what could go wrong.}"

  {
    echo "$SYSTEM_PROMPT"
    echo ""
    echo "Review this implementation plan:"
    echo ""
    cat "$WORK_DIR/plan.md"
    echo ""
    echo "Be specific and actionable. If the plan is solid and ready to implement, end your review with exactly: VERDICT: APPROVED"
    echo ""
    echo "If changes are needed, end with exactly: VERDICT: REVISE"
  } > "$WORK_DIR/${REVIEWER}-acpx-prompt.txt"

  PROMPT_FILE="$WORK_DIR/${REVIEWER}-acpx-prompt.txt"
fi

# --- Resolve timeout binary ---

TIMEOUT_BIN=""
if command -v timeout > /dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout > /dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
else
  echo "[$REVIEWER] WARNING: neither timeout nor gtimeout found — running without timeout enforcement" >&2
  echo "  Install: brew install coreutils (macOS) / apt install coreutils (Linux)" >&2
fi

# --- acpx call ---

echo "[$REVIEWER] Submitting plan to $AGENT via acpx (timeout: ${TIMEOUT}s)..." >&2

ACPX_CMD=()
if [ -n "$TIMEOUT_BIN" ] && [ "$TIMEOUT" -gt 0 ]; then
  ACPX_CMD+=("$TIMEOUT_BIN" "$TIMEOUT")
fi
ACPX_CMD+=("${ACPX_BIN[@]}" --format quiet --approve-reads "$AGENT" --file "$PROMPT_FILE")

set +e
"${ACPX_CMD[@]}" > "$WORK_DIR/${REVIEWER}-output.md" 2>"$WORK_DIR/${REVIEWER}-stderr.log"
EXIT_CODE=$?
set -e

# --- Handle exit codes ---

if [ "$EXIT_CODE" -eq 124 ]; then
  echo "[$REVIEWER] Timed out after ${TIMEOUT}s." >&2
elif [ "$EXIT_CODE" -ne 0 ]; then
  echo "[$REVIEWER] acpx failed (exit $EXIT_CODE)." >&2
  # Surface stderr for diagnostics
  if [ -s "$WORK_DIR/${REVIEWER}-stderr.log" ]; then
    echo "[$REVIEWER] stderr: $(head -5 "$WORK_DIR/${REVIEWER}-stderr.log")" >&2
  fi
  # If output is empty, populate from stderr
  if [ ! -s "$WORK_DIR/${REVIEWER}-output.md" ]; then
    {
      echo "acpx error (exit $EXIT_CODE) for agent '$AGENT':"
      echo ""
      cat "$WORK_DIR/${REVIEWER}-stderr.log" 2>/dev/null || echo "(no stderr)"
    } > "$WORK_DIR/${REVIEWER}-output.md"
  fi
else
  echo "[$REVIEWER] Review received." >&2
fi

echo "$EXIT_CODE" > "$WORK_DIR/${REVIEWER}-exit.txt"

# Check for empty successful response
if [ "$EXIT_CODE" -eq 0 ] && [ ! -s "$WORK_DIR/${REVIEWER}-output.md" ]; then
  echo "[$REVIEWER] Empty response from acpx." >&2
  {
    echo "Empty response from $AGENT via acpx. Stderr:"
    echo ""
    cat "$WORK_DIR/${REVIEWER}-stderr.log" 2>/dev/null || echo "(no stderr)"
  } > "$WORK_DIR/${REVIEWER}-output.md"
  echo "1" > "$WORK_DIR/${REVIEWER}-exit.txt"
  trap - EXIT
  exit 1
fi

trap - EXIT
exit "$EXIT_CODE"
