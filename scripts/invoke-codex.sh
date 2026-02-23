#!/bin/bash
# Single Codex reviewer invocation — initial call or session resume.
# Encapsulates all codex CLI flags, session capture, and
# resume-fallback logic so callers don't repeat the boilerplate.
#
# Usage: invoke-codex.sh <work_dir> [session_id] [model]
#   work_dir   — temp directory for this review (must contain plan.md)
#   session_id — optional; if set, attempts resume; falls back to fresh on failure
#   model      — optional; defaults to gpt-5.3-codex
#
# Env: TIMEOUT_BIN — optional path to timeout binary (timeout or gtimeout)
#
# Prompt selection:
#   If $work_dir/codex-prompt.txt exists, its contents are used as the prompt.
#   Otherwise (initial review), the standard Executor persona prompt is used.
#
# Output files (all written to $work_dir):
#   codex-output.md      review text
#   codex-stdout.txt     raw stdout (used for session ID extraction)
#   codex-exit.txt       exit code
#   codex-session-id.txt session ID for next resume (empty on failure)
#
# Note: codex exec resume does NOT support -o; its output goes to stdout.
#   The script copies stdout → codex-output.md for resume calls.

WORK_DIR="${1:-}"
SESSION_ID="${2:-}"
MODEL="${3:-gpt-5.3-codex}"

if [ -z "$WORK_DIR" ]; then
  echo "Usage: $0 <work_dir> [session_id] [model]" >&2
  exit 1
fi

if [ ! -d "$WORK_DIR" ]; then
  echo "invoke-codex.sh: work_dir does not exist: $WORK_DIR" >&2
  exit 1
fi

if [ ! -f "$WORK_DIR/plan.md" ]; then
  echo "invoke-codex.sh: plan.md not found in $WORK_DIR" >&2
  exit 1
fi

# Resolve timeout
if [ -z "${TIMEOUT_BIN:-}" ]; then
  TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
fi
if [ -n "$TIMEOUT_BIN" ]; then
  TIMEOUT_CMD=("$TIMEOUT_BIN" 120)
else
  TIMEOUT_CMD=()
fi

# Prompt selection
if [ -f "$WORK_DIR/codex-prompt.txt" ]; then
  PROMPT="$(cat "$WORK_DIR/codex-prompt.txt")"
else
  PROMPT="You are The Executor — a pragmatic runtime tracer. Review the implementation plan in $WORK_DIR/plan.md. Your job is to trace exactly what will happen at runtime. Assume nothing works until proven. Focus on:
1. Shell correctness — syntax errors, wrong flags, unquoted variables
2. Exit code handling — pipelines, \${PIPESTATUS}, timeout detection
3. Race conditions — PID capture, parallel job coordination, session ID timing
4. File I/O — are paths correct, do files exist before they are read, missing mkdir -p
5. Command availability — are all binaries assumed to be present without checking

Be specific and actionable. If the plan is solid and ready to implement, end your review with exactly: VERDICT: APPROVED

If changes are needed, end with exactly: VERDICT: REVISE"
fi

CODEX_EXIT=0
CALLED_RESUME=0

if [ -n "$SESSION_ID" ]; then
  # codex exec resume — output goes to stdout (no -o support)
  "${TIMEOUT_CMD[@]}" codex exec resume "$SESSION_ID" "$PROMPT" \
    2>&1 | tee "$WORK_DIR/codex-stdout.txt"
  CODEX_EXIT=${PIPESTATUS[0]}

  if [ "$CODEX_EXIT" -eq 124 ]; then
    echo "invoke-codex.sh: resume timed out (exit 124) — not falling back" >&2
    echo "124" > "$WORK_DIR/codex-exit.txt"
    : > "$WORK_DIR/codex-session-id.txt"
    exit 124
  elif [ "$CODEX_EXIT" -eq 0 ]; then
    CALLED_RESUME=1
  else
    echo "invoke-codex.sh: resume failed (exit $CODEX_EXIT) — falling back to fresh call" >&2
    SESSION_ID=""
  fi
fi

if [ -z "$SESSION_ID" ]; then
  # Fresh call — use -o for output file, tee stdout to capture session ID
  "${TIMEOUT_CMD[@]}" codex exec \
    -m "$MODEL" \
    -s read-only \
    -o "$WORK_DIR/codex-output.md" \
    "$PROMPT" \
    2>&1 | tee "$WORK_DIR/codex-stdout.txt"
  CODEX_EXIT=${PIPESTATUS[0]}
fi

echo "$CODEX_EXIT" > "$WORK_DIR/codex-exit.txt"

if [ "$CODEX_EXIT" -eq 0 ]; then
  if [ "$CALLED_RESUME" -eq 1 ]; then
    # Resume output is in stdout (no -o support); copy to standard output file
    cp "$WORK_DIR/codex-stdout.txt" "$WORK_DIR/codex-output.md"
  fi
  # Extract session ID from stdout
  grep -oE 'session id: [0-9a-f-]+' "$WORK_DIR/codex-stdout.txt" 2>/dev/null \
    | head -1 \
    | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
    > "$WORK_DIR/codex-session-id.txt" 2>/dev/null \
    || : > "$WORK_DIR/codex-session-id.txt"
else
  : > "$WORK_DIR/codex-session-id.txt"
fi

exit "$CODEX_EXIT"
