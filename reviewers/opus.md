---
name: opus
binary: claude
display_name: Anthropic Claude Opus
default_model: claude-opus-4-6
install_command: npm install -g @anthropic-ai/claude-code
---

# Opus Reviewer Definition

This file defines how to use the Claude CLI as a plan reviewer (Opus model).
Claude reads these instructions and interpolates `{placeholder}` values at runtime.

## Availability Check

```bash
which claude
which jq
```

If `claude` not found: `npm install -g @anthropic-ai/claude-code`
If `jq` not found: `brew install jq` (required to parse `--output-format json` output)

## Critical: Nested Session Guard

**Before any `claude` invocation**, unset the env vars that block nested calls:

```bash
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
```

Without this, `claude -p` exits immediately:
`Claude Code cannot be launched inside another Claude Code session`

## Initial Review

Plan content is passed via file path reference in the prompt string.
Use `--output-format json` — stdout contains both the review text (`.result`) and
session ID (`.session_id`). No stderr output in this mode.

```bash
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
CLAUDE_CODE_SIMPLE=1 "${TIMEOUT_CMD[@]}" claude -p \
  --model {model} \
  --tools "" \
  --disable-slash-commands \
  --strict-mcp-config \
  --settings '{"disableAllHooks":true}' \
  --output-format json \
  "You are The Skeptic — a devil's advocate. Your job is to find what everyone else missed. Be specific, be harsh, be right. Review the implementation plan in {plan_file}. Focus on:
1. Unstated assumptions — what is assumed true that could be false?
2. Unhappy path — what breaks when the first thing goes wrong?
3. Second-order failures — what does a partial success leave behind?
4. Security — is any user-controlled content reaching a shell string?
5. The one thing — if this plan has one fatal flaw, what is it?

Be specific and actionable. If the plan is solid, end with: VERDICT: APPROVED
If changes are needed, end with: VERDICT: REVISE" \
  > {json_file}
echo "$?" > {exit_file}

# Extract review text and session ID from JSON output
jq -r '.result // ""' {json_file} > {output_file}
OPUS_SESSION_ID=$(jq -r '.session_id // ""' {json_file})
```

**Verified**: `--output-format json` emits a single JSON object to stdout containing
`.result` (review text) and `.session_id` (UUID for resume). No stderr in this mode.

## Session ID Capture

Deterministic — parse from the JSON output file:

```bash
OPUS_SESSION_ID=$(jq -r '.session_id // ""' {json_file})
```

Store as `OPUS_SESSION_ID_{reviewer_name}`.

Always guard resume on a non-empty session ID:

```bash
if [ -n "$OPUS_SESSION_ID" ]; then
  # resume call
else
  # fall back to fresh call, recapture session ID
fi
```

## Session Resume

```bash
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
CLAUDE_CODE_SIMPLE=1 "${TIMEOUT_CMD[@]}" claude --resume "$OPUS_SESSION_ID" -p "{prompt}" \
  --tools "" \
  --disable-slash-commands \
  --strict-mcp-config \
  --settings '{"disableAllHooks":true}' \
  --output-format json \
  > {json_file}
jq -r '.result // ""' {json_file}
```

If resume fails (non-zero exit or empty output), fall back to a fresh call and
recapture `OPUS_SESSION_ID` from the new `.session_id` field.

## Output

- Initial review: `.result` extracted from JSON via jq → `{output_file}`
- Session ID: `.session_id` extracted from JSON via jq → stored in var
- Resume output: `.result` extracted from JSON via jq → stdout
