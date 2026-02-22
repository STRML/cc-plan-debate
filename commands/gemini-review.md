---
description: Send the current plan to Google Gemini CLI for iterative review. Claude and Gemini go back-and-forth until Gemini approves or max 5 rounds reached.
allowed-tools: Bash(uuidgen:*), Bash(command -v:*), Bash(mkdir -p /tmp/ai-review-:*), Bash(rm -rf /tmp/ai-review-:*), Bash(gemini -p:*), Bash(gemini --list-sessions:*), Bash(gemini --resume:*), Bash(which gemini:*), Bash(timeout:*), Bash(gtimeout:*), Bash(diff:*)
---

# Gemini Plan Review (Iterative)

Send the current implementation plan to Google Gemini for review. Claude revises the plan based on Gemini's feedback and re-submits until Gemini approves. Max 5 rounds.

---

## Prerequisite Check

Before starting, verify Gemini CLI is available and authenticated:

```bash
which gemini
```

If `gemini` is not found, stop and display:

```
Gemini CLI is not installed.

Install it with:
  npm install -g @google/gemini-cli

Then authenticate:
  gemini auth

After installing, re-run /debate:gemini-review.
```

If `gemini` is found, check authentication:

```bash
gemini --list-sessions > /dev/null 2>&1
```

If this fails (non-zero exit), warn: `Gemini is not authenticated. Run: gemini auth`

## Step 1: Setup

**Model:** Check if a model argument was passed (e.g., `/debate:gemini-review gemini-2.0-flash`). If so, use it. Default: `gemini-3.1-pro-preview`. Store as `MODEL`.

**Timeout command:** Resolve once and build as an array — macOS ships `gtimeout` (coreutils), Linux ships `timeout`:

```bash
TIMEOUT_BIN=$(command -v timeout || command -v gtimeout || true)
if [ -n "$TIMEOUT_BIN" ]; then
  TIMEOUT_CMD=("$TIMEOUT_BIN" 120)
else
  echo "Warning: neither 'timeout' nor 'gtimeout' found. Install: brew install coreutils"
  echo "Proceeding without timeout protection."
  TIMEOUT_CMD=()
fi
```

Invoke as `"${TIMEOUT_CMD[@]}" gemini ...` — when `TIMEOUT_CMD` is empty this reduces to just `gemini ...` with no timeout.

**Session ID and temp dir:**

```bash
REVIEW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | head -c 8)
mkdir -p /tmp/ai-review-${REVIEW_ID}
```

Temp file paths:
- Plan file: `/tmp/ai-review-${REVIEW_ID}/plan.md`
- Gemini output: `/tmp/ai-review-${REVIEW_ID}/gemini-output.md`
- Sessions before: `/tmp/ai-review-${REVIEW_ID}/sessions-before.txt`
- Sessions after: `/tmp/ai-review-${REVIEW_ID}/sessions-after.txt`

**Cleanup:** If any step fails or the user interrupts, always run `rm -rf /tmp/ai-review-${REVIEW_ID}` before stopping.

## Step 2: Capture the Plan

Write the current plan to the temp file:

1. Write the full plan content to `/tmp/ai-review-${REVIEW_ID}/plan.md`
2. If there is no plan in the current context, ask the user what they want reviewed

## Step 3: Initial Review (Round 1)

**Snapshot session list before the call:**

```bash
gemini --list-sessions 2>/dev/null > /tmp/ai-review-${REVIEW_ID}/sessions-before.txt
```

Run Gemini with plan content via stdin redirect (not pipe — stdin redirect gives correct `$?` for the Gemini/timeout process). Use `-e ""` to disable extensions/skills for efficiency:

```bash
"${TIMEOUT_CMD[@]}" gemini \
  -p "Review this implementation plan (provided via stdin). Focus on:
1. Correctness - Will this plan achieve the stated goals?
2. Risks - What could go wrong? Edge cases? Data loss?
3. Missing steps - Is anything forgotten?
4. Alternatives - Is there a simpler or better approach?
5. Security - Any security concerns?

Be specific and actionable. If the plan is solid and ready to implement, end your review with exactly: VERDICT: APPROVED

If changes are needed, end with exactly: VERDICT: REVISE" \
  -m $MODEL \
  -s \
  -e "" \
  < /tmp/ai-review-${REVIEW_ID}/plan.md \
  > /tmp/ai-review-${REVIEW_ID}/gemini-output.md 2>&1
GEMINI_EXIT=$?
```

If `GEMINI_EXIT` is `124`, Gemini timed out — inform the user and stop.

**Capture the Gemini session UUID** by diffing the session list:

```bash
gemini --list-sessions 2>/dev/null > /tmp/ai-review-${REVIEW_ID}/sessions-after.txt
diff /tmp/ai-review-${REVIEW_ID}/sessions-before.txt \
     /tmp/ai-review-${REVIEW_ID}/sessions-after.txt
```

Find the new entry and extract the UUID from the `[uuid]` field. Store as `GEMINI_SESSION_UUID`.

If the diff shows multiple new sessions (concurrent usage), prefer the entry whose title most closely matches the plan content. If still ambiguous, set `GEMINI_SESSION_UUID=""` and skip resume in subsequent rounds (fall back to fresh calls).

**Notes:**
- Use `-m $MODEL` (resolved from args above; defaults to `gemini-3.1-pro-preview`)
- Use `-s` (sandbox) so Gemini cannot execute shell commands
- Use `-e ""` to disable all extensions — reduces startup overhead and suppresses skill loading
- Use stdin redirect (`< plan.md`) not a pipe — gives correct exit code for timeout detection

## Step 4: Read Review & Check Verdict

1. Read `/tmp/ai-review-${REVIEW_ID}/gemini-output.md`
2. Present Gemini's review:

```
## Gemini Review — Round N (model: $MODEL)

[Gemini's feedback here]
```

3. Check the verdict:
   - If **VERDICT: APPROVED** → go to Step 7 (Done)
   - If **VERDICT: REVISE** → go to Step 5 (Revise & Re-submit)
   - If no clear verdict but feedback is all positive / no actionable items → treat as approved
   - If max rounds (5) reached → go to Step 7 with a note that max rounds hit

## Step 5: Revise the Plan

Based on Gemini's feedback:

1. **Revise the plan** — address each issue Gemini raised. Update the plan content in the conversation context and rewrite `/tmp/ai-review-${REVIEW_ID}/plan.md` with the revised version.
2. **Write the revision summary to a file** (never compose this inline in a shell string):

```bash
cat > /tmp/ai-review-${REVIEW_ID}/revisions.txt << 'EOF'
[Write the revision bullets here before closing the heredoc]
EOF
```

3. Summarize changes for the user:

```
### Revisions (Round N)
- [What was changed and why, one bullet per Gemini issue addressed]
```

4. Inform the user what's happening: "Sending revised plan back to Gemini for re-review..."

## Step 6: Re-submit to Gemini (Rounds 2–5)

If `GEMINI_SESSION_UUID` is set, resume the existing session. The updated plan is again passed via stdin redirect.

Build the resume prompt from files:

```bash
{
  echo "I've revised the plan based on your feedback. The updated plan is provided via stdin."
  echo ""
  echo "Here's what I changed:"
  cat /tmp/ai-review-${REVIEW_ID}/revisions.txt
  echo ""
  echo "Please re-review the updated plan. If it is now solid and ready to implement, end with: VERDICT: APPROVED"
  echo "If more changes are needed, end with: VERDICT: REVISE"
} > /tmp/ai-review-${REVIEW_ID}/resume-prompt.txt

RESUME_PROMPT=$(cat /tmp/ai-review-${REVIEW_ID}/resume-prompt.txt)
"${TIMEOUT_CMD[@]}" gemini \
  --resume $GEMINI_SESSION_UUID \
  -p "$RESUME_PROMPT" \
  -s \
  -e "" \
  < /tmp/ai-review-${REVIEW_ID}/plan.md \
  > /tmp/ai-review-${REVIEW_ID}/gemini-output.md 2>&1
GEMINI_EXIT=$?
```

If resume fails (`GEMINI_EXIT` non-zero, or UUID is empty):
- Fall back to a fresh Gemini call (same flags as Step 3, with prior-round context prepended in the prompt via file)
- After the fresh call, recapture `GEMINI_SESSION_UUID` by diffing `--list-sessions` again — do NOT continue using the old UUID

Then go back to **Step 4** (Read Review & Check Verdict).

## Step 7: Present Final Result

Once approved (or max rounds reached):

```
## Gemini Review — Final (model: $MODEL)

**Status:** ✅ Approved after N round(s)

[Final Gemini feedback / approval message]

---
**The plan has been reviewed and approved by Gemini. Ready for your approval to implement.**
```

If max rounds were reached without approval:

```
## Gemini Review — Final (model: $MODEL)

**Status:** ⚠️ Max rounds (5) reached — not fully approved

**Remaining concerns:**
[List unresolved issues from last review]

---
**Gemini still has concerns. Review the remaining items and decide whether to proceed or continue refining.**
```

## Step 8: Cleanup

```bash
rm -rf /tmp/ai-review-${REVIEW_ID}
```

If any step failed before reaching this step, still run this cleanup.

## Loop Summary

```
Round 1: Claude sends plan → Gemini reviews → REVISE?
Round 2: Claude revises → Gemini re-reviews (resume session) → REVISE?
Round 3: Claude revises → Gemini re-reviews (resume session) → APPROVED ✅
```

Max 5 rounds. Each round preserves Gemini's conversation context via session resume.

## Rules

- Claude **actively revises the plan** based on Gemini feedback between rounds — this is NOT just passing messages, Claude should make real improvements
- Default model is `gemini-3.1-pro-preview`. Accept model override from the user's arguments (e.g., `/debate:gemini-review gemini-2.0-flash`)
- Always use `-s` (sandbox mode) — Gemini should never execute shell commands
- Always use `-e ""` — suppresses skill/extension loading for efficiency
- Always use stdin redirect (`< plan.md`) not a pipe — ensures correct exit code for timeout detection
- Always capture Gemini session UUID by diffing `--list-sessions` before/after — never use positional indexes or `latest`
- Never interpolate AI-generated text directly into shell strings — always build via file operations
- Max 5 review rounds to prevent infinite loops
- Show the user each round's feedback and revisions so they can follow along
- If Gemini CLI is not installed or fails, inform the user and suggest `npm install -g @google/gemini-cli && gemini auth`
- If a revision contradicts the user's explicit requirements, skip that revision and note it for the user
