#!/bin/bash
# Generic reviewer invocation via any OpenAI-compatible API.
# Stateless — no session resume. Each call sends full context.
#
# Usage: invoke-openai-compat.sh <config_file> <work_dir> <reviewer_name> [model] [timeout]
#   config_file   — path to JSON config (e.g. ~/.claude/debate-openrouter.json)
#   work_dir      — temp directory (must contain plan.md)
#   reviewer_name — e.g. "deepseek", "gemini", "opus"
#   model         — optional override; falls back to config value
#   timeout       — optional override; falls back to config value, then 120s
#
# Config schema:
#   {
#     "base_url": "https://openrouter.ai/api/v1",
#     "api_key": "sk-or-...",
#     "api_key_env": "OPENROUTER_API_KEY",
#     "headers": { "X-Title": "cc-debate" },
#     "reviewers": {
#       "<name>": {
#         "model": "...",
#         "timeout": 120,
#         "system_prompt": "..."
#       }
#     }
#   }
#
# Prompt resolution (in order):
#   1. $work_dir/<name>-prompt.txt  (debate/revision rounds write this)
#   2. reviewers.<name>.system_prompt from config
#   3. Built-in fallback: generic plan reviewer
#
# Plan content is always read from plan.md and injected into the user message.
#
# Output files (all written to $work_dir):
#   <name>-output.md   review text
#   <name>-raw.json    full API response (for debugging)
#   <name>-exit.txt    exit code (0=success, 124=timeout, 1=error)

set -euo pipefail

CONFIG_FILE="${1:-}"
WORK_DIR="${2:-}"
REVIEWER="${3:-}"
MODEL_ARG="${4:-}"
TIMEOUT_ARG="${5:-}"

if [ -z "$CONFIG_FILE" ] || [ -z "$WORK_DIR" ] || [ -z "$REVIEWER" ]; then
  echo "Usage: $0 <config_file> <work_dir> <reviewer_name> [model] [timeout]" >&2
  exit 1
fi

# --- Trap: ensure exit file is always written ---

create_exit_file() {
  local code="${1:-1}"
  local reason="${2:-unknown error}"
  if [ -n "$WORK_DIR" ] && [ -n "$REVIEWER" ]; then
    echo "$code" > "$WORK_DIR/${REVIEWER}-exit.txt"
    if [ ! -f "$WORK_DIR/${REVIEWER}-output.md" ]; then
      echo "invoke-openai-compat: $reason" > "$WORK_DIR/${REVIEWER}-output.md"
    fi
  fi
}

trap 'create_exit_file "$?" "unexpected exit"' EXIT

if [ ! -d "$WORK_DIR" ]; then
  echo "invoke-openai-compat: work_dir does not exist: $WORK_DIR" >&2
  exit 1
fi

if [ ! -f "$WORK_DIR/plan.md" ]; then
  echo "invoke-openai-compat: plan.md not found in $WORK_DIR" >&2
  exit 1
fi

# --- Config ---

if [ ! -f "$CONFIG_FILE" ]; then
  echo "invoke-openai-compat: config not found: $CONFIG_FILE" >&2
  exit 1
fi

BASE_URL=$(jq -r '.base_url // empty' "$CONFIG_FILE")
if [ -z "$BASE_URL" ]; then
  echo "invoke-openai-compat: base_url is required in $CONFIG_FILE" >&2
  exit 1
fi
BASE_URL="${BASE_URL%/}"
API_KEY=$(jq -r '.api_key // ""' "$CONFIG_FILE")
CONFIG_MODEL=$(jq -r --arg rev "$REVIEWER" '.reviewers[$rev].model // empty' "$CONFIG_FILE")
CONFIG_TIMEOUT=$(jq -r --arg rev "$REVIEWER" '.reviewers[$rev].timeout // empty' "$CONFIG_FILE")
CONFIG_SYSTEM_PROMPT=$(jq -r --arg rev "$REVIEWER" '.reviewers[$rev].system_prompt // empty' "$CONFIG_FILE")

# Resolve: CLI arg > config > error/default
MODEL="${MODEL_ARG:-${CONFIG_MODEL:-}}"
if [ -z "$MODEL" ]; then
  echo "invoke-openai-compat: no model for '$REVIEWER' (pass as arg or set in config)" >&2
  exit 1
fi

TIMEOUT="${TIMEOUT_ARG:-${CONFIG_TIMEOUT:-120}}"
if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -le 0 ]; then
  echo "invoke-openai-compat: invalid timeout '$TIMEOUT' for '$REVIEWER', using 120s" >&2
  TIMEOUT=120
fi
# API key: config api_key > config api_key_env > deprecation check > empty
if [ -z "$API_KEY" ]; then
  API_KEY_ENV=$(jq -r '.api_key_env // empty' "$CONFIG_FILE")
  if [ -n "$API_KEY_ENV" ]; then
    API_KEY="${!API_KEY_ENV:-}"
  fi
fi

if [ -z "$API_KEY" ] && [ -n "${LITELLM_API_KEY:-}" ]; then
  echo "WARNING: LITELLM_API_KEY is set but not referenced in config." >&2
  echo "  Add \"api_key_env\": \"LITELLM_API_KEY\" to $CONFIG_FILE" >&2
fi

# --- Prompt ---

SYSTEM_PROMPT=""
USER_PROMPT=""
PLAN_CONTENT="$(cat "$WORK_DIR/plan.md")"

if [ -f "$WORK_DIR/${REVIEWER}-prompt.txt" ]; then
  # Debate/revision round — prompt file is the full user message
  USER_PROMPT="$(cat "$WORK_DIR/${REVIEWER}-prompt.txt")"
else
  # Initial review — use system prompt + plan as user message
  if [ -n "$CONFIG_SYSTEM_PROMPT" ]; then
    SYSTEM_PROMPT="$CONFIG_SYSTEM_PROMPT"
  else
    SYSTEM_PROMPT="You are a senior engineer reviewing an implementation plan. Be specific, direct, and focus on what could go wrong."
  fi

  USER_PROMPT="Review this implementation plan:

$PLAN_CONTENT

Be specific and actionable. If the plan is solid and ready to implement, end your review with exactly: VERDICT: APPROVED

If changes are needed, end with exactly: VERDICT: REVISE"
fi

# --- Build JSON payload (jq handles all escaping) ---

if [ -n "$SYSTEM_PROMPT" ]; then
  PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --arg user "$USER_PROMPT" \
    '{
      model: $model,
      messages: [
        { role: "system", content: $system },
        { role: "user", content: $user }
      ],
      temperature: 0.3
    }')
else
  PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg user "$USER_PROMPT" \
    '{
      model: $model,
      messages: [
        { role: "user", content: $user }
      ],
      temperature: 0.3
    }')
fi

# --- API call ---

echo "[$REVIEWER] Submitting plan to $MODEL via $BASE_URL (timeout: ${TIMEOUT}s)..." >&2

CURL_ARGS=(
  -s -S
  --max-time "$TIMEOUT"
  -H "Content-Type: application/json"
)

# --- Extra headers from config ---
HEADER_KEYS=$(jq -r '.headers // {} | keys[]' "$CONFIG_FILE" 2>/dev/null) || true
while IFS= read -r hkey; do
  [ -z "$hkey" ] && continue
  hval=$(jq -r --arg k "$hkey" '.headers[$k]' "$CONFIG_FILE")
  # Reject \r and \n (null bytes can't exist in bash strings)
  if [[ "$hkey" == *$'\r'* ]] || [[ "$hkey" == *$'\n'* ]]; then
    echo "invoke-openai-compat: invalid header key containing control chars: '$hkey'" >&2
    exit 1
  fi
  if [[ "$hval" == *$'\r'* ]] || [[ "$hval" == *$'\n'* ]]; then
    echo "invoke-openai-compat: invalid header value for '$hkey' containing control chars" >&2
    exit 1
  fi
  CURL_ARGS+=(-H "$hkey: $hval")
done <<< "$HEADER_KEYS"

if [ -n "$API_KEY" ]; then
  CURL_ARGS+=(-H "Authorization: Bearer $API_KEY")
fi

CURL_ARGS+=(-d "$PAYLOAD" "${BASE_URL}/chat/completions")

set +e
curl "${CURL_ARGS[@]}" > "$WORK_DIR/${REVIEWER}-raw.json" 2>"$WORK_DIR/${REVIEWER}-stderr.log"
EXIT_CODE=$?
set -e

# --- Handle curl exit codes ---

if [ "$EXIT_CODE" -eq 28 ] || [ "$EXIT_CODE" -eq 124 ]; then
  echo "[$REVIEWER] Timed out after ${TIMEOUT}s." >&2
  echo "124" > "$WORK_DIR/${REVIEWER}-exit.txt"
  trap - EXIT
  exit 124
elif [ "$EXIT_CODE" -ne 0 ]; then
  echo "[$REVIEWER] curl failed (exit $EXIT_CODE)." >&2
  {
    echo "curl error (exit $EXIT_CODE):"
    cat "$WORK_DIR/${REVIEWER}-stderr.log"
  } > "$WORK_DIR/${REVIEWER}-output.md"
  echo "$EXIT_CODE" > "$WORK_DIR/${REVIEWER}-exit.txt"
  trap - EXIT
  exit "$EXIT_CODE"
fi

# --- Parse response ---

PARSE_ERR=0
CONTENT=$(jq -r '.choices[0].message.content // empty' "$WORK_DIR/${REVIEWER}-raw.json" 2>/dev/null) || PARSE_ERR=1
ERROR=$(jq -r '.error.message // empty' "$WORK_DIR/${REVIEWER}-raw.json" 2>/dev/null) || PARSE_ERR=1

if [ "$PARSE_ERR" -ne 0 ] && [ -z "$CONTENT" ] && [ -z "$ERROR" ]; then
  echo "[$REVIEWER] Failed to parse API response (non-JSON or malformed)." >&2
  {
    echo "Failed to parse response from $MODEL (non-JSON or malformed). Raw body:"
    echo ""
    cat "$WORK_DIR/${REVIEWER}-raw.json" 2>/dev/null || echo "(no raw file)"
  } > "$WORK_DIR/${REVIEWER}-output.md"
  echo "1" > "$WORK_DIR/${REVIEWER}-exit.txt"
  trap - EXIT
  exit 1
fi

if [ -n "$ERROR" ]; then
  echo "[$REVIEWER] API error: $ERROR" >&2
  echo "API error from $MODEL: $ERROR" > "$WORK_DIR/${REVIEWER}-output.md"
  echo "1" > "$WORK_DIR/${REVIEWER}-exit.txt"
  trap - EXIT
  exit 1
fi

if [ -z "$CONTENT" ]; then
  echo "[$REVIEWER] Empty response from API." >&2
  {
    echo "Empty response from $MODEL. Raw JSON:"
    echo ""
    cat "$WORK_DIR/${REVIEWER}-raw.json"
  } > "$WORK_DIR/${REVIEWER}-output.md"
  echo "1" > "$WORK_DIR/${REVIEWER}-exit.txt"
  trap - EXIT
  exit 1
fi

echo "$CONTENT" > "$WORK_DIR/${REVIEWER}-output.md"
echo "0" > "$WORK_DIR/${REVIEWER}-exit.txt"
echo "[$REVIEWER] Review received." >&2

trap - EXIT
exit 0
