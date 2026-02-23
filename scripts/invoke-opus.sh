#!/bin/bash
# Single Opus reviewer invocation — initial call or session resume.
# Encapsulates all claude CLI flags, JSON parsing, session capture,
# and resume-fallback logic so callers don't repeat the boilerplate.
#
# Usage: invoke-opus.sh <work_dir> [session_id] [model]
#   work_dir   — temp directory for this review (must contain plan.md)
#   session_id — optional; if set, attempts --resume; falls back to fresh on failure
#   model      — optional; defaults to claude-opus-4-6
#
# Env: TIMEOUT_BIN — optional path to timeout binary (timeout or gtimeout)
#
# Prompt selection:
#   If $work_dir/opus-prompt.txt exists, its contents are used as the prompt.
#   Otherwise (initial review), the standard Skeptic persona prompt is used.
#
# Output files (all written to $work_dir):
#   opus-raw.json       full JSON response from claude
#   opus-output.md      extracted review text (.result)
#   opus-exit.txt       exit code of the claude invocation
#   opus-session-id.txt session ID for next resume (empty on failure)

WORK_DIR="${1:-}"
SESSION_ID="${2:-}"
MODEL="${3:-claude-opus-4-6}"

if [ -z "$WORK_DIR" ]; then
  echo "Usage: $0 <work_dir> [session_id] [model]" >&2
  exit 1
fi

if [ ! -d "$WORK_DIR" ]; then
  echo "invoke-opus.sh: work_dir does not exist: $WORK_DIR" >&2
  exit 1
fi

if [ ! -f "$WORK_DIR/plan.md" ]; then
  echo "invoke-opus.sh: plan.md not found in $WORK_DIR" >&2
  exit 1
fi

# Resolve timeout — inherit TIMEOUT_BIN from environment or detect
if [ -z "${TIMEOUT_BIN:-}" ]; then
  TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
fi
if [ -n "$TIMEOUT_BIN" ]; then
  OPUS_TIMEOUT_CMD=("$TIMEOUT_BIN" 300)
else
  OPUS_TIMEOUT_CMD=()
fi

# Standard Opus flags shared by every invocation
CLAUDE_FLAGS=(
  --effort medium
  --tools ""
  --disable-slash-commands
  --strict-mcp-config
  --settings '{"disableAllHooks":true}'
  --output-format json
)

# Prompt: use opus-prompt.txt if present (resume/debate/revision rounds),
# otherwise use the hardcoded initial Skeptic persona prompt.
if [ -f "$WORK_DIR/opus-prompt.txt" ]; then
  PROMPT="$(cat "$WORK_DIR/opus-prompt.txt")"
else
  PROMPT="You are The Skeptic — a devil's advocate. Your job is to find what everyone else missed. Be specific, be harsh, be right. Review the implementation plan in $WORK_DIR/plan.md. Focus on:
1. Unstated assumptions — what is assumed true that could be false?
2. Unhappy path — what breaks when the first thing goes wrong?
3. Second-order failures — what does a partial success leave behind?
4. Security — is any user-controlled content reaching a shell string?
5. The one thing — if this plan has one fatal flaw, what is it?

Be specific and actionable. If the plan is solid and ready to implement, end your review with exactly: VERDICT: APPROVED

If changes are needed, end with exactly: VERDICT: REVISE"
fi

# Always unset nested-session guard before invoking claude
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT

OPUS_EXIT=0

if [ -n "$SESSION_ID" ]; then
  # Attempt session resume
  "${OPUS_TIMEOUT_CMD[@]}" env CLAUDE_CODE_SIMPLE=1 claude --resume "$SESSION_ID" \
    -p "$PROMPT" \
    "${CLAUDE_FLAGS[@]}" \
    > "$WORK_DIR/opus-raw.json"
  OPUS_EXIT=$?

  if [ "$OPUS_EXIT" -eq 124 ]; then
    echo "invoke-opus.sh: resume timed out (exit 124) — not falling back" >&2
    echo "124" > "$WORK_DIR/opus-exit.txt"
    : > "$WORK_DIR/opus-session-id.txt"
    exit 124
  elif [ "$OPUS_EXIT" -ne 0 ]; then
    echo "invoke-opus.sh: resume failed (exit $OPUS_EXIT) — falling back to fresh call" >&2
    SESSION_ID=""
  fi
fi

if [ -z "$SESSION_ID" ]; then
  # Fresh call (either initial or fallback from failed resume)
  "${OPUS_TIMEOUT_CMD[@]}" env CLAUDE_CODE_SIMPLE=1 claude \
    --model "$MODEL" \
    -p "$PROMPT" \
    "${CLAUDE_FLAGS[@]}" \
    > "$WORK_DIR/opus-raw.json"
  OPUS_EXIT=$?
fi

if [ "$OPUS_EXIT" -eq 0 ]; then
  jq -r '.result // ""' "$WORK_DIR/opus-raw.json" > "$WORK_DIR/opus-output.md"
  JQ_EXIT=$?
  if [ "$JQ_EXIT" -ne 0 ]; then
    echo "invoke-opus.sh: failed to parse JSON from claude output" >&2
    OPUS_EXIT=1
    : > "$WORK_DIR/opus-output.md"
    : > "$WORK_DIR/opus-session-id.txt"
  else
    jq -r '.session_id // ""' "$WORK_DIR/opus-raw.json" > "$WORK_DIR/opus-session-id.txt"
  fi
else
  : > "$WORK_DIR/opus-session-id.txt"
fi

echo "$OPUS_EXIT" > "$WORK_DIR/opus-exit.txt"

exit "$OPUS_EXIT"
