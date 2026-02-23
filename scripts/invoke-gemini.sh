#!/bin/bash
# Single Gemini reviewer invocation — initial call or session resume.
# Encapsulates all gemini CLI flags, session UUID capture, and
# resume-fallback logic so callers don't repeat the boilerplate.
#
# Usage: invoke-gemini.sh <work_dir> [session_uuid] [model]
#   work_dir     — temp directory for this review (must contain plan.md)
#   session_uuid — optional; if set, attempts --resume; falls back to fresh on failure
#   model        — optional; defaults to gemini-3.1-pro-preview
#
# Env: TIMEOUT_BIN — optional path to timeout binary (timeout or gtimeout)
#
# Prompt selection:
#   If $work_dir/gemini-prompt.txt exists, its contents are used as the -p prompt.
#   Otherwise (initial review), the standard Architect persona prompt is used.
#
# Plan content is always passed via stdin redirect (< plan.md).
#
# Output files (all written to $work_dir):
#   gemini-output.md           review text
#   gemini-exit.txt            exit code
#   gemini-session-id.txt      session UUID for next resume (empty on failure)
#
# Session capture: finds new session-*.json files in ~/.gemini/tmp/ created during
# the call (via -newer marker file), reads .sessionId from JSON. Avoids
# gemini --list-sessions which hangs in the Claude Code sandbox.

WORK_DIR="${1:-}"
SESSION_UUID="${2:-}"
MODEL="${3:-gemini-3.1-pro-preview}"

if [ -z "$WORK_DIR" ]; then
  echo "Usage: $0 <work_dir> [session_uuid] [model]" >&2
  exit 1
fi

if [ ! -d "$WORK_DIR" ]; then
  echo "invoke-gemini.sh: work_dir does not exist: $WORK_DIR" >&2
  exit 1
fi

if [ ! -f "$WORK_DIR/plan.md" ]; then
  echo "invoke-gemini.sh: plan.md not found in $WORK_DIR" >&2
  exit 1
fi

# Resolve timeout
if [ -z "${TIMEOUT_BIN:-}" ]; then
  TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
fi
GEMINI_TIMEOUT="${GEMINI_TIMEOUT:-240}"
if [ -n "$TIMEOUT_BIN" ]; then
  TIMEOUT_CMD=("$TIMEOUT_BIN" "$GEMINI_TIMEOUT")
else
  TIMEOUT_CMD=()
fi

# Prompt selection
if [ -f "$WORK_DIR/gemini-prompt.txt" ]; then
  PROMPT="$(cat "$WORK_DIR/gemini-prompt.txt")"
else
  PROMPT="You are The Architect — a systems architect reviewing for structural integrity. Review this implementation plan (provided via stdin). Think big picture before line-by-line. Focus on:
1. Approach validity — is this the right solution to the actual problem?
2. Over-engineering — what could be simplified or removed?
3. Missing phases — is anything structurally absent from the flow?
4. Graceful degradation — does the design hold when parts fail?
5. Alternatives — is there a meaningfully better approach?

Be specific and actionable. If the plan is solid and ready to implement, end your review with exactly: VERDICT: APPROVED

If changes are needed, end with exactly: VERDICT: REVISE"
fi

# Mark timestamp before call so we can find the new session file via -newer
touch "$WORK_DIR/gemini-call-start"

GEMINI_EXIT=0

if [ -n "$SESSION_UUID" ]; then
  # Resume call
  "${TIMEOUT_CMD[@]}" gemini \
    --resume "$SESSION_UUID" \
    -p "$PROMPT" \
    -m "$MODEL" \
    -s \
    -e "" \
    < "$WORK_DIR/plan.md" \
    > "$WORK_DIR/gemini-output.md" 2>"$WORK_DIR/gemini-stderr.log"
  GEMINI_EXIT=$?

  if [ "$GEMINI_EXIT" -eq 124 ]; then
    echo "invoke-gemini.sh: resume timed out (exit 124) — not falling back" >&2
    echo "124" > "$WORK_DIR/gemini-exit.txt"
    : > "$WORK_DIR/gemini-session-id.txt"
    exit 124
  elif [ "$GEMINI_EXIT" -ne 0 ]; then
    echo "invoke-gemini.sh: resume failed (exit $GEMINI_EXIT) — falling back to fresh call" >&2
    SESSION_UUID=""
  fi
fi

if [ -z "$SESSION_UUID" ]; then
  # Fresh call
  "${TIMEOUT_CMD[@]}" gemini \
    -p "$PROMPT" \
    -m "$MODEL" \
    -s \
    -e "" \
    < "$WORK_DIR/plan.md" \
    > "$WORK_DIR/gemini-output.md" 2>"$WORK_DIR/gemini-stderr.log"
  GEMINI_EXIT=$?
fi

echo "$GEMINI_EXIT" > "$WORK_DIR/gemini-exit.txt"

# Capture session UUID by reading the new session file from ~/.gemini/tmp
# (avoids gemini --list-sessions which hangs in sandbox)
NEW_UUID=$(find ~/.gemini/tmp -name "session-*.json" -newer "$WORK_DIR/gemini-call-start" 2>/dev/null \
  | xargs -I{} jq -r '.sessionId // empty' {} 2>/dev/null \
  | head -1 || echo "")

if [ -n "$NEW_UUID" ]; then
  echo "$NEW_UUID" > "$WORK_DIR/gemini-session-id.txt"
elif [ -n "$SESSION_UUID" ] && [ "$GEMINI_EXIT" -eq 0 ]; then
  # Resume succeeded but no new session entry; keep existing UUID
  echo "$SESSION_UUID" > "$WORK_DIR/gemini-session-id.txt"
else
  : > "$WORK_DIR/gemini-session-id.txt"
fi

exit "$GEMINI_EXIT"
