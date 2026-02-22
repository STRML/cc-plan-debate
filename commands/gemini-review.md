---
description: Send the current plan to Google Gemini CLI for iterative review. Claude and Gemini go back-and-forth until Gemini approves or max 5 rounds reached.
allowed-tools: Bash(uuidgen:*), Bash(command -v:*), Bash(mkdir -p /tmp/ai-review-:*), Bash(rm -rf /tmp/ai-review-:*), Bash(gemini -p:*), Bash(gemini --list-sessions:*), Bash(gemini --resume:*), Bash(which gemini:*), Bash(timeout:*), Bash(gtimeout:*), Bash(cat /tmp/ai-review-:*)
---

# Gemini Plan Review (Iterative)

Send the current implementation plan to Google Gemini for review. Claude revises the plan based on Gemini's feedback and re-submits until Gemini approves. Max 5 rounds.

---

## Prerequisite Check

Before starting, verify Gemini CLI is available:

```bash
which gemini
```

If `gemini` is not found, stop and display this message:

```
Gemini CLI is not installed.

Install it with:
  npm install -g @google/gemini-cli

Then authenticate:
  gemini auth

After installing, re-run /debate:gemini-review.
```

## Step 1: Setup

**Model:** Check if a model argument was passed (e.g., `/debate:gemini-review gemini-2.0-flash`). If so, use it. Default: `gemini-3.1-pro-preview`. Store as `MODEL`.

**Timeout binary:** Resolve once — macOS ships `gtimeout` (coreutils), Linux ships `timeout`:

```bash
TIMEOUT_BIN=$(command -v timeout || command -v gtimeout)
```

If neither is found, warn the user (`Install GNU coreutils`) and proceed without a timeout wrapper.

**Session ID and temp dir:**

```bash
REVIEW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | head -c 8)
mkdir -p /tmp/ai-review-${REVIEW_ID}
```

Temp file paths:
- Plan file: `/tmp/ai-review-${REVIEW_ID}/plan.md`
- Gemini output: `/tmp/ai-review-${REVIEW_ID}/gemini-output.md`

**Cleanup:** If any step fails or the user interrupts, always run `rm -rf /tmp/ai-review-${REVIEW_ID}` before stopping.

## Step 2: Capture the Plan

Write the current plan to the temp file:

1. Write the full plan content to `/tmp/ai-review-${REVIEW_ID}/plan.md`
2. If there is no plan in the current context, ask the user what they want reviewed

## Step 3: Initial Review (Round 1)

**Snapshot the session list before the call** so you can identify the new session by diffing after:

```bash
gemini --list-sessions 2>/dev/null > /tmp/ai-review-${REVIEW_ID}/sessions-before.txt
```

Plan content is passed via stdin — never inlined in the `-p` prompt string. The `-e ""` flag disables extensions (including skills) to minimize overhead and improve cache hit rate:

```bash
cat /tmp/ai-review-${REVIEW_ID}/plan.md | $TIMEOUT_BIN 120 gemini \
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
  > /tmp/ai-review-${REVIEW_ID}/gemini-output.md
```

If exit code is `124`, Gemini timed out — inform the user and stop.

**Capture the Gemini session UUID** by diffing the session list:

```bash
gemini --list-sessions 2>/dev/null > /tmp/ai-review-${REVIEW_ID}/sessions-after.txt
```

Parse the new session's UUID from the diff (the entry in `sessions-after.txt` that wasn't in `sessions-before.txt`). It appears in the format `[<uuid>]`. Store as `GEMINI_SESSION_UUID`.

Use this exact UUID for resume — do NOT use positional indexes (`--resume 0`) which shift when sessions are deleted, and do NOT use `--resume latest` which is race-prone when multiple reviews run concurrently.

**Notes:**
- Use `-m $MODEL` (resolved from args above; defaults to `gemini-3.1-pro-preview`)
- Use `-s` (sandbox) so Gemini cannot execute shell commands
- Use `-e ""` to disable all extensions — reduces startup overhead and avoids skill loading
- Plan content goes through stdin, never into `-p`, to avoid shell argument length limits on large plans

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
2. **Briefly summarize** what you changed for the user:

```
### Revisions (Round N)
- [What was changed and why, one bullet per Gemini issue addressed]
```

3. Inform the user what's happening: "Sending revised plan back to Gemini for re-review..."

## Step 6: Re-submit to Gemini (Rounds 2–5)

Resume the existing Gemini session. The updated plan is again passed via stdin.

**Write the resume prompt to a file first** — never interpolate dynamic content (revision list, AI feedback) directly into a quoted shell string, as it may contain characters that break shell parsing:

```bash
cat > /tmp/ai-review-${REVIEW_ID}/resume-prompt.txt << 'PROMPTEOF'
I've revised the plan based on your feedback. The updated plan is provided via stdin.

Here's what I changed:
[List the specific changes made — fill this in before writing the file]

Please re-review the updated plan. If it is now solid and ready to implement, end with: VERDICT: APPROVED
If more changes are needed, end with: VERDICT: REVISE
PROMPTEOF
```

Fill in the revision list before writing the file, then resume:

```bash
RESUME_PROMPT=$(cat /tmp/ai-review-${REVIEW_ID}/resume-prompt.txt)
cat /tmp/ai-review-${REVIEW_ID}/plan.md | $TIMEOUT_BIN 120 gemini \
  --resume $GEMINI_SESSION_UUID \
  -p "$RESUME_PROMPT" \
  -s \
  -e "" \
  2>&1
```

If resume fails (session expired or UUID stale), fall back to a fresh `cat plan.md | gemini -p "..."` call and include a summary of prior rounds in the prompt.

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

Remove the session-scoped temporary files:
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
- Plan content always goes through stdin pipe, never inlined in the `-p` flag — avoids shell arg length limits on large plans
- Always capture Gemini session UUID by diffing `--list-sessions` before/after — never use positional indexes or `latest`
- Never interpolate AI-generated text directly into shell strings — always write to a temp file first
- Max 5 review rounds to prevent infinite loops
- Show the user each round's feedback and revisions so they can follow along
- If Gemini CLI is not installed or fails, inform the user and suggest `npm install -g @google/gemini-cli && gemini auth`
- If a revision contradicts the user's explicit requirements, skip that revision and note it for the user
