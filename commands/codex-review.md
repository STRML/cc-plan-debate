---
description: Send the current plan to OpenAI Codex CLI for iterative review. Claude and Codex go back-and-forth until Codex approves or max 5 rounds reached.
allowed-tools: Bash(uuidgen:*), Bash(mkdir -p /tmp/ai-review-:*), Bash(rm -rf /tmp/ai-review-:*), Bash(codex exec -m:*), Bash(codex exec resume:*), Bash(which codex:*)
---

# Codex Plan Review (Iterative)

Send the current implementation plan to OpenAI Codex for review. Claude revises the plan based on Codex's feedback and re-submits until Codex approves. Max 5 rounds.

---

## Prerequisite Check

Before starting, verify Codex CLI is available:

```bash
which codex
```

If `codex` is not found, stop and display this message:

```
Codex CLI is not installed.

Install it with:
  npm install -g @openai/codex

Then ensure you have configured your OpenAI API key:
  export OPENAI_API_KEY=<your-key>

After installing, re-run /codex-review.
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
- Codex output: `/tmp/ai-review-${REVIEW_ID}/codex-output.md`

## Step 2: Capture the Plan

Write the current plan to the temp file:

1. Write the full plan content to `/tmp/ai-review-${REVIEW_ID}/plan.md`
2. If there is no plan in the current context, ask the user what they want reviewed

## Step 3: Initial Review (Round 1)

Accept optional model override from command argument (e.g., `/codex-review o4-mini`). Default: `gpt-5.3-codex`.

Run Codex in non-interactive mode:

```bash
codex exec \
  -m gpt-5.3-codex \
  -s read-only \
  -o /tmp/ai-review-${REVIEW_ID}/codex-output.md \
  "Review the implementation plan in /tmp/ai-review-${REVIEW_ID}/plan.md. Focus on:
1. Correctness - Will this plan achieve the stated goals?
2. Risks - What could go wrong? Edge cases? Data loss?
3. Missing steps - Is anything forgotten?
4. Alternatives - Is there a simpler or better approach?
5. Security - Any security concerns?

Be specific and actionable. If the plan is solid and ready to implement, end your review with exactly: VERDICT: APPROVED

If changes are needed, end with exactly: VERDICT: REVISE"
```

**Capture the Codex session ID** from the output line that says `session id: <uuid>`. Store as `CODEX_SESSION_ID`. Use this exact ID for resume — do NOT use `--last` which is race-prone with concurrent sessions.

## Step 4: Read Review & Check Verdict

1. Read `/tmp/ai-review-${REVIEW_ID}/codex-output.md`
2. Present Codex's review:

```
## Codex Review — Round N (model: gpt-5.3-codex)

[Codex's feedback here]
```

3. Check the verdict:
   - **VERDICT: APPROVED** → go to Step 7 (Done)
   - **VERDICT: REVISE** → go to Step 5 (Revise & Re-submit)
   - No clear verdict but all-positive feedback → treat as approved
   - Max rounds (5) reached → go to Step 7 with a max-rounds note

## Step 5: Revise the Plan

Based on Codex's feedback:

1. Revise the plan — address each issue raised. Update the conversation context and rewrite `/tmp/ai-review-${REVIEW_ID}/plan.md`.
2. Summarize changes:

```
### Revisions (Round N)
- [What was changed and why, one bullet per issue addressed]
```

3. Inform the user: "Sending revised plan back to Codex for re-review..."

## Step 6: Re-submit to Codex (Rounds 2–5)

Resume the existing Codex session for full context:

```bash
codex exec resume ${CODEX_SESSION_ID} \
  "I've revised the plan based on your feedback. The updated plan is in /tmp/ai-review-${REVIEW_ID}/plan.md.

Here's what I changed:
[List the specific changes made]

Please re-review. If the plan is now solid and ready to implement, end with: VERDICT: APPROVED
If more changes are needed, end with: VERDICT: REVISE" 2>&1 | tail -80
```

**Note:** `codex exec resume` does NOT support `-o`. Read from stdout.

If resume fails (session expired), fall back to a fresh `codex exec` call with context about prior rounds included in the prompt.

Then return to **Step 4**.

## Step 7: Present Final Result

**Approved:**
```
## Codex Review — Final (model: gpt-5.3-codex)

**Status:** ✅ Approved after N round(s)

[Final Codex feedback / approval message]

---
The plan has been reviewed and approved by Codex. Ready for your approval to implement.
```

**Max rounds reached without approval:**
```
## Codex Review — Final (model: gpt-5.3-codex)

**Status:** ⚠️ Max rounds (5) reached — not fully approved

**Remaining concerns:**
[List unresolved issues from last review]

---
Codex still has concerns. Review the remaining items and decide whether to proceed or continue refining.
```

## Step 8: Cleanup

```bash
rm -rf /tmp/ai-review-${REVIEW_ID}
```

---

## Rules

- Claude **actively revises the plan** based on feedback — this is not just message passing
- Default model: `gpt-5.3-codex`. Accept override from command args (e.g., `/codex-review o4-mini`)
- Always use read-only sandbox mode (`-s read-only`) — Codex must never write files
- Max 5 review rounds
- Show each round's feedback and revisions so the user can follow along
- If a revision contradicts the user's explicit requirements, skip it and note it
