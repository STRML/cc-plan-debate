---
description: Send the current plan to OpenAI Codex CLI for iterative review. Claude and Codex go back-and-forth until Codex approves or max 5 rounds reached.
allowed-tools: Bash(uuidgen:*), Bash(command -v:*), Bash(mkdir -p /tmp/claude/ai-review-:*), Bash(rm -rf /tmp/claude/ai-review-:*), Bash(which codex:*), Bash(timeout:*), Bash(gtimeout:*), Bash(bash ~/.claude/plugins/cache/debate-dev/debate/1.0.0/scripts/invoke-codex.sh:*), Bash(codex exec -m:*), Bash(codex exec resume:*)
---

# Codex Plan Review (Iterative)

Send the current implementation plan to OpenAI Codex for review. Claude revises the plan based on Codex's feedback and re-submits until Codex approves. Max 5 rounds.

Codex plays the role of **The Executor** — a pragmatic runtime tracer focused on shell correctness, exit codes, race conditions, and file I/O.

---

## Prerequisite Check

Before starting, verify Codex CLI is available:

```bash
which codex
```

If `codex` is not found, stop and display:

```text
Codex CLI is not installed.

Install it with:
  npm install -g @openai/codex

Then ensure you have configured your OpenAI API key:
  export OPENAI_API_KEY=<your-key>

After installing, re-run /debate:codex-review.
```

## Step 1: Setup

**Model:** Check if a model argument was passed (e.g., `/debate:codex-review o4-mini`). If so, use it. Default: `gpt-5.3-codex`. Store as `MODEL`.

**Script and timeout:**

```bash
SCRIPT_DIR=~/.claude/plugins/cache/debate-dev/debate/1.0.0/scripts
TIMEOUT_BIN=$(command -v timeout || command -v gtimeout || true)
[ -z "$TIMEOUT_BIN" ] && echo "Warning: timeout not found. Install: brew install coreutils"
```

**Session ID and temp dir:**

```bash
REVIEW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | head -c 8)
mkdir -p /tmp/claude/ai-review-${REVIEW_ID}
```

Temp directory: `/tmp/claude/ai-review-${REVIEW_ID}/`
Key files: `plan.md`, `codex-output.md`, `codex-session-id.txt`, `codex-exit.txt`

**Cleanup:** If any step fails or the user interrupts, always run `rm -rf /tmp/claude/ai-review-${REVIEW_ID}` before stopping.

## Step 2: Capture the Plan

1. Write the full plan content to `/tmp/claude/ai-review-${REVIEW_ID}/plan.md`
2. If there is no plan in the current context, ask the user what they want reviewed

## Step 3: Initial Review (Round 1)

Run the Codex reviewer script (handles all codex flags, session capture, and retry logic internally):

```bash
TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-codex.sh" \
  "/tmp/claude/ai-review-${REVIEW_ID}" "" "$MODEL"
CODEX_EXIT=$?
if [ "$CODEX_EXIT" -eq 124 ]; then
  echo "Codex timed out after 120s."; rm -rf /tmp/claude/ai-review-${REVIEW_ID}; exit 1
elif [ "$CODEX_EXIT" -ne 0 ]; then
  echo "Codex failed (exit $CODEX_EXIT)."; rm -rf /tmp/claude/ai-review-${REVIEW_ID}; exit 1
fi
CODEX_SESSION_ID=$(cat /tmp/claude/ai-review-${REVIEW_ID}/codex-session-id.txt 2>/dev/null || echo "")
```

The script writes the review to `codex-output.md` and the session ID to `codex-session-id.txt`.

## Step 4: Read Review & Check Verdict

1. Read `/tmp/claude/ai-review-${REVIEW_ID}/codex-output.md`
2. Present Codex's review:

```text
## Codex Review — Round N (model: $MODEL)

[Codex's feedback here]
```

3. Check the verdict:
   - If **VERDICT: APPROVED** → go to Step 7 (Done)
   - If **VERDICT: REVISE** → go to Step 5 (Revise & Re-submit)
   - If no clear verdict but feedback is all positive / no actionable items → treat as approved
   - If max rounds (5) reached → go to Step 7 with a note that max rounds hit

## Step 5: Revise the Plan

Based on Codex's feedback:

1. **Revise the plan** — address each issue Codex raised. Update the plan content in the conversation context and rewrite `/tmp/claude/ai-review-${REVIEW_ID}/plan.md` with the revised version.
2. **Write the revision summary to a file** (never compose this inline in a shell string):

```bash
cat > /tmp/claude/ai-review-${REVIEW_ID}/revisions.txt << 'EOF'
[Write the revision bullets here before closing the heredoc]
EOF
```

3. Summarize changes for the user:

```text
### Revisions (Round N)
- [What was changed and why, one bullet per Codex issue addressed]
```

4. Inform the user what's happening: "Sending revised plan back to Codex for re-review..."

## Step 6: Re-submit to Codex (Rounds 2–5)

Write the resume prompt, then call the script — it handles resume vs fresh-fallback internally:

```bash
{
  echo "I've revised the plan based on your feedback. The updated plan is in /tmp/claude/ai-review-${REVIEW_ID}/plan.md."
  echo ""
  echo "Here's what I changed:"
  cat /tmp/claude/ai-review-${REVIEW_ID}/revisions.txt
  echo ""
  echo "Please re-review. If the plan is now solid and ready to implement, end with: VERDICT: APPROVED"
  echo "If more changes are needed, end with: VERDICT: REVISE"
} > /tmp/claude/ai-review-${REVIEW_ID}/codex-prompt.txt

TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-codex.sh" \
  "/tmp/claude/ai-review-${REVIEW_ID}" "$CODEX_SESSION_ID" "$MODEL"
CODEX_EXIT=$?
if [ "$CODEX_EXIT" -eq 124 ]; then
  echo "Codex timed out — stopping."; rm -rf /tmp/claude/ai-review-${REVIEW_ID}; exit 1
elif [ "$CODEX_EXIT" -ne 0 ]; then
  echo "Codex failed (exit $CODEX_EXIT) — stopping."; rm -rf /tmp/claude/ai-review-${REVIEW_ID}; exit 1
fi
CODEX_SESSION_ID=$(cat /tmp/claude/ai-review-${REVIEW_ID}/codex-session-id.txt 2>/dev/null || echo "")
```

Then go back to **Step 4** (Read Review & Check Verdict).

## Step 7: Present Final Result

Once approved (or max rounds reached):

```text
## Codex Review — Final (model: $MODEL)

**Status:** ✅ Approved after N round(s)

[Final Codex feedback / approval message]

---
**The plan has been reviewed and approved by Codex. Ready for your approval to implement.**
```

If max rounds were reached without approval:

```text
## Codex Review — Final (model: $MODEL)

**Status:** ⚠️ Max rounds (5) reached — not fully approved

**Remaining concerns:**
[List unresolved issues from last review]

---
**Codex still has concerns. Review the remaining items and decide whether to proceed or continue refining.**
```

## Step 8: Cleanup

```bash
rm -rf /tmp/claude/ai-review-${REVIEW_ID}
```

## Loop Summary

```text
Round 1: Claude sends plan → Codex reviews → REVISE?
Round 2: Claude revises → Codex re-reviews (resume session) → REVISE?
Round 3: Claude revises → Codex re-reviews (resume session) → APPROVED ✅
```

Max 5 rounds. Each round preserves Codex's conversation context via session resume.

## Rules

- Claude **actively revises the plan** based on Codex feedback between rounds — not just passing messages
- Default model is `gpt-5.3-codex`. Accept model override from the user's arguments (e.g., `/debate:codex-review o4-mini`)
- Always use read-only sandbox mode — Codex should never write files
- Max 5 review rounds to prevent infinite loops
- Show the user each round's feedback and revisions so they can follow along
- Never interpolate AI-generated text directly into shell strings — always build via file operations
- If a revision contradicts the user's explicit requirements, skip that revision and note it for the user
