---
name: opus
binary: claude
display_name: Anthropic Claude Opus
default_model: claude-opus-4-6
install_command: npm install -g @anthropic-ai/claude-code
---

# Opus Reviewer Definition

Defines how to invoke the Claude CLI as The Skeptic reviewer.
All invocation logic (flags, session capture, resume fallback) is
encapsulated in `scripts/invoke-opus.sh`. This file serves as
reference documentation and the persona definition.

## Availability Check

```bash
which claude
which jq
```

If `claude` not found: `npm install -g @anthropic-ai/claude-code`
If `jq` not found: `brew install jq` (required to parse `--output-format json` output)

## Persona

**The Skeptic** — a devil's advocate. Job: find what everyone else missed.

Focus areas:
1. Unstated assumptions — what is assumed true that could be false?
2. Unhappy path — what breaks when the first thing goes wrong?
3. Second-order failures — what does a partial success leave behind?
4. Security — is any user-controlled content reaching a shell string?
5. The one thing — if this plan has one fatal flaw, what is it?

## How to Invoke

All callers use `scripts/invoke-opus.sh`:

```bash
# Initial review (no session ID, no opus-prompt.txt needed)
TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-opus.sh" "$WORK_DIR" "" "$MODEL"

# Resume round (write prompt to opus-prompt.txt first)
{
  echo "Revised plan is in $WORK_DIR/plan.md."
  echo "Here's what changed: ..."
} > "$WORK_DIR/opus-prompt.txt"
TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-opus.sh" "$WORK_DIR" "$OPUS_SESSION_ID" "$MODEL"

# After each call:
OPUS_EXIT=$?
OPUS_SESSION_ID=$(cat "$WORK_DIR/opus-session-id.txt" 2>/dev/null || echo "")
```

Output files written to `$WORK_DIR`:
- `opus-output.md` — extracted review text
- `opus-session-id.txt` — session ID for next resume (empty on failure)
- `opus-exit.txt` — exit code (0 = success, 124 = timeout)
- `opus-raw.json` — full JSON response (for debugging)

## CLI Flags (canonical, in invoke-opus.sh)

```bash
env CLAUDE_CODE_SIMPLE=1 claude -p \
  --model claude-opus-4-6 \
  --effort medium \
  --tools "" \
  --disable-slash-commands \
  --strict-mcp-config \
  --settings '{"disableAllHooks":true}' \
  --output-format json
```

- `unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT` — required before every invocation
- `CLAUDE_CODE_SIMPLE=1` — no plugin/skill loading
- `--effort medium` — balanced quality vs latency
- `--tools ""` — no tool access
- `--output-format json` — `.result` is review text, `.session_id` is resume key

## Session Resume Notes

- Session ID is parsed from `.session_id` in the JSON stdout (not stderr — stderr is empty)
- On resume failure, `invoke-opus.sh` automatically falls back to a fresh call
- After fallback, a new session ID is captured from the fresh response
- The prompt for fallback fresh calls comes from `opus-prompt.txt` if present,
  otherwise the hardcoded initial Skeptic prompt is used
