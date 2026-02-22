---
description: Send the current plan to Google Gemini CLI for iterative review. Claude and Gemini go back-and-forth until Gemini approves or max 5 rounds reached.
allowed-tools: Bash(uuidgen:*), Bash(mkdir -p /tmp/ai-review-:*), Bash(rm -rf /tmp/ai-review-:*), Bash(gemini -p:*), Bash(gemini --list-sessions:*), Bash(gemini --resume:*), Bash(which gemini:*), Bash(cat /tmp/ai-review-:*)
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

After installing, re-run /gemini-review.
```

## Step 1: Generate Session ID

```bash
REVIEW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | head -c 8)
```

Create a session-scoped temp directory:
```bash
mkdir -p /tmp/ai-review-${REVIEW_ID}
```

Use these paths:
- Plan file: `/tmp/ai-review-${REVIEW_ID}/plan.md`
- Gemini output: `/tmp/ai-review-${REVIEW_ID}/gemini-output.md`

## Step 2: Capture the Plan

Write the current plan to the temp file:

1. Write the full plan content to `/tmp/ai-review-${REVIEW_ID}/plan.md`
2. If there is no plan in the current context, ask the user what they want reviewed

## Step 3: Initial Review (Round 1)

Accept optional model override from command argument (e.g., `/gemini-review gemini-2.0-flash`). Default: `gemini-3.1-pro-preview`.

Plan content is passed via stdin — never inlined in the `-p` prompt string:

```bash
cat /tmp/ai-review-${REVIEW_ID}/plan.md | gemini \
  -p "Review this implementation plan (provided via stdin). Focus on:
1. Correctness - Will this plan achieve the stated goals?
2. Risks - What could go wrong? Edge cases? Data loss?
3. Missing steps - Is anything forgotten?
4. Alternatives - Is there a simpler or better approach?
5. Security - Any security concerns?

Be specific and actionable. If the plan is solid and ready to implement, end your review with exactly: VERDICT: APPROVED

If changes are needed, end with exactly: VERDICT: REVISE" \
  -m gemini-3.1-pro-preview \
  --approval-mode=plan \
  > /tmp/ai-review-${REVIEW_ID}/gemini-output.md
```

**Capture session index:** After the initial call, run:
```bash
gemini --list-sessions | head -3
```
Read the most recent session index (typically `0` or `1`). Store as `GEMINI_SESSION_IDX`. You MUST use this exact index to resume in subsequent rounds — do NOT use `--resume latest`, which would grab the wrong session if multiple reviews are running concurrently.

**Notes:**
- Use `-m gemini-3.1-pro-preview` as the default model. If the user specifies a different model (e.g., `/gemini-review gemini-2.0-flash`), use that instead.
- Use `--approval-mode=plan` so Gemini cannot execute shell commands — it can only review.
- Plan content is always piped via stdin so there is no shell argument length limit on large plans.
- Output is captured via stdout redirect to the output file for reliable reading.

## Step 4: Read Review & Check Verdict

1. Read `/tmp/ai-review-${REVIEW_ID}/gemini-output.md`
2. Present Gemini's review:

```
## Gemini Review — Round N (model: gemini-3.1-pro-preview)

[Gemini's feedback here]
```

3. Check the verdict:
   - **VERDICT: APPROVED** → go to Step 7 (Done)
   - **VERDICT: REVISE** → go to Step 5 (Revise & Re-submit)
   - No clear verdict but all-positive feedback → treat as approved
   - Max rounds (5) reached → go to Step 7 with a max-rounds note

## Step 5: Revise the Plan

Based on Gemini's feedback:

1. Revise the plan — address each issue raised. Update the conversation context and rewrite `/tmp/ai-review-${REVIEW_ID}/plan.md`.
2. Summarize changes:

```
### Revisions (Round N)
- [What was changed and why, one bullet per issue addressed]
```

3. Inform the user: "Sending revised plan back to Gemini for re-review..."

## Step 6: Re-submit to Gemini (Rounds 2–5)

Resume the existing Gemini session for full context. The updated plan is again passed via stdin:

```bash
cat /tmp/ai-review-${REVIEW_ID}/plan.md | gemini \
  --resume ${GEMINI_SESSION_IDX} \
  -p "I've revised the plan based on your feedback. The updated plan is provided via stdin.

Here's what I changed:
[List the specific changes made]

Please re-review the updated plan. If it is now solid and ready to implement, end with: VERDICT: APPROVED
If more changes are needed, end with: VERDICT: REVISE" \
  --approval-mode=plan 2>&1
```

If resume fails (session expired or index stale), fall back to a fresh `cat plan.md | gemini -p "..."` call and include a summary of prior rounds in the prompt.

Then return to **Step 4**.

## Step 7: Present Final Result

**Approved:**
```
## Gemini Review — Final (model: gemini-3.1-pro-preview)

**Status:** ✅ Approved after N round(s)

[Final Gemini feedback / approval message]

---
**The plan has been reviewed and approved by Gemini. Ready for your approval to implement.**
```

**Max rounds reached without approval:**
```
## Gemini Review — Final (model: gemini-3.1-pro-preview)

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

---

## Loop Summary

```
Round 1: Claude sends plan → Gemini reviews → REVISE?
Round 2: Claude revises → Gemini re-reviews (resume session) → REVISE?
Round 3: Claude revises → Gemini re-reviews (resume session) → APPROVED ✅
```

Max 5 rounds. Each round preserves Gemini's conversation context via session resume.

## Rules

- Claude **actively revises the plan** based on Gemini feedback between rounds — this is NOT just passing messages, Claude should make real improvements
- Default model is `gemini-3.1-pro-preview`. Accept model override from the user's arguments (e.g., `/gemini-review gemini-2.0-flash`)
- Always use `--approval-mode=plan` — Gemini should never execute shell commands
- Plan content always goes through stdin pipe, never inlined in the `-p` flag — avoids shell arg length limits on large plans
- Max 5 review rounds to prevent infinite loops
- Show the user each round's feedback and revisions so they can follow along
- If Gemini CLI is not installed or fails, inform the user and suggest `npm install -g @google/gemini-cli && gemini auth`
- If a revision contradicts the user's explicit requirements, skip that revision and note it for the user
