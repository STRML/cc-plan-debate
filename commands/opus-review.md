---
description: Send the current plan to Claude Opus for iterative review. Claude and Opus go back-and-forth until Opus approves or max 5 rounds reached.
allowed-tools: Bash(uuidgen:*), Bash(command -v:*), Bash(mkdir -p /tmp/claude/ai-review-:*), Bash(rm -rf /tmp/claude/ai-review-:*), Bash(claude -p:*), Bash(claude --resume:*), Bash(which claude:*), Bash(which jq:*), Bash(jq:*), Bash(timeout:*), Bash(gtimeout:*)
---

# Opus Plan Review (Iterative)

Send the current implementation plan to Claude Opus for review. Claude revises the plan based on Opus's feedback and re-submits until Opus approves. Max 5 rounds.

Opus plays the role of **The Skeptic** — a devil's advocate focused on unstated assumptions, unhappy paths, second-order failures, and security.

---

## Prerequisite Check

Before starting, verify Claude CLI and jq are available:

```bash
which claude
which jq
```

If `claude` is not found, stop and display:

```text
Claude CLI is not installed.

Install it with:
  npm install -g @anthropic-ai/claude-code

After installing, re-run /debate:opus-review.
```

If `jq` is not found, stop and display:

```text
jq is not installed. It is required to parse Claude's JSON output.

Install it with:
  brew install jq   (macOS)
  apt install jq    (Linux)

After installing, re-run /debate:opus-review.
```

## Step 1: Setup

**Model:** Check if a model argument was passed (e.g., `/debate:opus-review claude-opus-4-5`). If so, use it. Default: `claude-opus-4-6`. Store as `MODEL`.

**Timeout command:** Resolve once and build as an array — macOS ships `gtimeout` (coreutils), Linux ships `timeout`:

```bash
TIMEOUT_BIN=$(command -v timeout || command -v gtimeout || true)
if [ -n "$TIMEOUT_BIN" ]; then
  TIMEOUT_CMD=("$TIMEOUT_BIN" 300)
else
  echo "Warning: neither 'timeout' nor 'gtimeout' found. Install: brew install coreutils"
  echo "Proceeding without timeout protection."
  TIMEOUT_CMD=()
fi
```

Invoke as `"${TIMEOUT_CMD[@]}" claude -p ...` — when `TIMEOUT_CMD` is empty this reduces to just `claude -p ...` with no timeout.

**Session ID and temp dir:**

```bash
REVIEW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | head -c 8)
mkdir -p /tmp/claude/ai-review-${REVIEW_ID}
```

Temp file paths:
- Plan file: `/tmp/claude/ai-review-${REVIEW_ID}/plan.md`
- Opus JSON output: `/tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json`
- Opus review text: `/tmp/claude/ai-review-${REVIEW_ID}/opus-output.md`
- Opus exit code: `/tmp/claude/ai-review-${REVIEW_ID}/opus-exit.txt`

**Cleanup:** If any step fails or the user interrupts, always run `rm -rf /tmp/claude/ai-review-${REVIEW_ID}` before stopping.

## Step 2: Capture the Plan

Write the current plan to the temp file:

1. Write the full plan content to `/tmp/claude/ai-review-${REVIEW_ID}/plan.md`
2. If there is no plan in the current context, ask the user what they want reviewed

## Step 3: Initial Review (Round 1)

Unset nested-session guard, then run Claude in non-interactive mode with `--output-format json`:

```bash
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
"${TIMEOUT_CMD[@]}" env CLAUDE_CODE_SIMPLE=1 claude -p \
  --model "$MODEL" \
  --effort medium \
  --tools "" \
  --disable-slash-commands \
  --strict-mcp-config \
  --settings '{"disableAllHooks":true}' \
  --output-format json \
  "You are The Skeptic — a devil's advocate. Your job is to find what everyone else missed. Be specific, be harsh, be right. Review the implementation plan in /tmp/claude/ai-review-${REVIEW_ID}/plan.md. Focus on:
1. Unstated assumptions — what is assumed true that could be false?
2. Unhappy path — what breaks when the first thing goes wrong?
3. Second-order failures — what does a partial success leave behind?
4. Security — is any user-controlled content reaching a shell string?
5. The one thing — if this plan has one fatal flaw, what is it?

Be specific and actionable. If the plan is solid and ready to implement, end your review with exactly: VERDICT: APPROVED

If changes are needed, end with exactly: VERDICT: REVISE" \
  > /tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json
OPUS_EXIT=$?
if [ "$OPUS_EXIT" -eq 124 ]; then
  echo "Opus timed out after 300s."
  rm -rf /tmp/claude/ai-review-${REVIEW_ID}; exit 1
elif [ "$OPUS_EXIT" -ne 0 ]; then
  echo "Opus failed (exit $OPUS_EXIT)."
  rm -rf /tmp/claude/ai-review-${REVIEW_ID}; exit 1
else
  jq -r '.result // ""' /tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json \
    > /tmp/claude/ai-review-${REVIEW_ID}/opus-output.md
  OPUS_SESSION_ID=$(jq -r '.session_id // ""' /tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json)
fi
```

**Notes:**
- `unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT` is required — without it, `claude -p` exits immediately inside an active Claude session
- `--output-format json` emits `.result` (review text) and `.session_id` in a single JSON object on stdout. No stderr output.
- `CLAUDE_CODE_SIMPLE=1` disables plugin/skill loading for efficiency
- `--tools ""` — no tool access
- `--disable-slash-commands` — no skills
- `--strict-mcp-config` — no MCP servers
- `--settings '{"disableAllHooks":true}'` — no hooks

## Step 4: Read Review & Check Verdict

1. Read `/tmp/claude/ai-review-${REVIEW_ID}/opus-output.md`
2. Present Opus's review:

```text
## Opus Review — Round N (model: $MODEL)

[Opus's feedback here]
```

3. Check the verdict:
   - If **VERDICT: APPROVED** → go to Step 7 (Done)
   - If **VERDICT: REVISE** → go to Step 5 (Revise & Re-submit)
   - If no clear verdict but feedback is all positive / no actionable items → treat as approved
   - If max rounds (5) reached → go to Step 7 with a note that max rounds hit

## Step 5: Revise the Plan

Based on Opus's feedback:

1. **Revise the plan** — address each issue Opus raised. Update the plan content in the conversation context and rewrite `/tmp/claude/ai-review-${REVIEW_ID}/plan.md` with the revised version.
2. **Write the revision summary to a file** (never compose this inline in a shell string):

```bash
cat > /tmp/claude/ai-review-${REVIEW_ID}/revisions.txt << 'EOF'
[Write the revision bullets here before closing the heredoc]
EOF
```

3. Summarize changes for the user:

```text
### Revisions (Round N)
- [What was changed and why, one bullet per Opus issue addressed]
```

4. Inform the user what's happening: "Sending revised plan back to Opus for re-review..."

## Step 6: Re-submit to Opus (Rounds 2–5)

If `OPUS_SESSION_ID` is set, resume the existing session. Build the resume prompt from files:

```bash
{
  echo "I've revised the plan based on your feedback. The updated plan is in /tmp/claude/ai-review-${REVIEW_ID}/plan.md."
  echo ""
  echo "Here's what I changed:"
  cat /tmp/claude/ai-review-${REVIEW_ID}/revisions.txt
  echo ""
  echo "Please re-review. If the plan is now solid and ready to implement, end with: VERDICT: APPROVED"
  echo "If more changes are needed, end with: VERDICT: REVISE"
} > /tmp/claude/ai-review-${REVIEW_ID}/resume-prompt.txt

```

**If `OPUS_SESSION_ID` is non-empty:**
```bash
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
"${TIMEOUT_CMD[@]}" env CLAUDE_CODE_SIMPLE=1 claude --resume "$OPUS_SESSION_ID" \
  -p "$(cat /tmp/claude/ai-review-${REVIEW_ID}/resume-prompt.txt)" \
  --effort medium \
  --tools "" \
  --disable-slash-commands \
  --strict-mcp-config \
  --settings '{"disableAllHooks":true}' \
  --output-format json \
  > /tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json
OPUS_EXIT=$?
if [ "$OPUS_EXIT" -eq 0 ]; then
  jq -r '.result // ""' /tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json \
    > /tmp/claude/ai-review-${REVIEW_ID}/opus-output.md
  NEW_SID=$(jq -r '.session_id // ""' /tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json)
  [ -n "$NEW_SID" ] && OPUS_SESSION_ID="$NEW_SID"
else
  # Resume failed — fall back to fresh call
  unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
  "${TIMEOUT_CMD[@]}" env CLAUDE_CODE_SIMPLE=1 claude -p \
    "$(cat /tmp/claude/ai-review-${REVIEW_ID}/resume-prompt.txt)" \
    --model "$MODEL" \
    --effort medium \
    --tools "" \
    --disable-slash-commands \
    --strict-mcp-config \
    --settings '{"disableAllHooks":true}' \
    --output-format json \
    > /tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json
  FRESH_EXIT=$?
  if [ "$FRESH_EXIT" -eq 124 ]; then
    echo "Warning: Opus fresh call timed out — stopping."
    rm -rf /tmp/claude/ai-review-${REVIEW_ID}; exit 1
  elif [ "$FRESH_EXIT" -ne 0 ]; then
    echo "Warning: Opus fresh call failed (exit $FRESH_EXIT) — stopping."
    rm -rf /tmp/claude/ai-review-${REVIEW_ID}; exit 1
  else
    jq -r '.result // ""' /tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json \
      > /tmp/claude/ai-review-${REVIEW_ID}/opus-output.md
    OPUS_SESSION_ID=$(jq -r '.session_id // ""' /tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json)
  fi
fi
```

**Note on prompt passing:** The resume prompt references a pre-written file (`resume-prompt.txt`) and uses `$(cat file)` inline — this is acceptable since the shell only does word splitting and globbing on unquoted expansions; double-quoting prevents both. There is no stdin alternative for `claude --resume -p`.

Then go back to **Step 4** (Read Review & Check Verdict).

## Step 7: Present Final Result

Once approved (or max rounds reached):

```text
## Opus Review — Final (model: $MODEL)

**Status:** ✅ Approved after N round(s)

[Final Opus feedback / approval message]

---
**The plan has been reviewed and approved by Opus. Ready for your approval to implement.**
```

If max rounds were reached without approval:

```text
## Opus Review — Final (model: $MODEL)

**Status:** ⚠️ Max rounds (5) reached — not fully approved

**Remaining concerns:**
[List unresolved issues from last review]

---
**Opus still has concerns. Review the remaining items and decide whether to proceed or continue refining.**
```

## Step 8: Cleanup

```bash
rm -rf /tmp/claude/ai-review-${REVIEW_ID}
```

If any step failed before reaching this step, still run this cleanup.

## Loop Summary

```text
Round 1: Claude sends plan → Opus reviews → REVISE?
Round 2: Claude revises → Opus re-reviews (resume session) → REVISE?
Round 3: Claude revises → Opus re-reviews (resume session) → APPROVED ✅
```

Max 5 rounds. Each round preserves Opus's conversation context via session resume.

## Rules

- Claude **actively revises the plan** based on Opus feedback between rounds — this is NOT just passing messages, Claude should make real improvements
- Default model is `claude-opus-4-6`. Accept model override from the user's arguments (e.g., `/debate:opus-review claude-opus-4-5`)
- Always `unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT` before every `claude` invocation
- Always use `--output-format json` and extract `.result` via jq — never grep stderr for session IDs
- Always guard resume: `[ -n "$OPUS_SESSION_ID" ]` before using `--resume`; fall back to fresh call if empty
- `jq` is required — stop and display install instructions if missing
- Max 5 review rounds to prevent infinite loops
- Show the user each round's feedback and revisions so they can follow along
- Never interpolate AI-generated text directly into shell strings — always build via file operations
- If a revision contradicts the user's explicit requirements, skip that revision and note it for the user
