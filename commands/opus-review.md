---
description: Send the current plan to Claude Opus for iterative review. Claude and Opus go back-and-forth until Opus approves or max 5 rounds reached.
allowed-tools: ToolSearch(*), TeamCreate(*), TeamDelete(*), SendMessage(*), Task(subagent_type: general-purpose)
---

# Opus Plan Review (Iterative)

Send the current implementation plan to Claude Opus for review. Claude revises the plan based on Opus's feedback and re-submits until Opus approves or 5 rounds are reached.

Opus plays the role of **The Skeptic** — a devil's advocate focused on unstated assumptions, unhappy paths, second-order failures, and security.

---

## Step 1: Capture the Plan

If there is no plan in the current context, ask the user what they want reviewed.

Set `CURRENT_PLAN` = the plan text. Set `ROUND = 1`. Set `MAX_ROUNDS = 5`.

---

## Step 2: Choose Execution Mode

Use ToolSearch to check if `TeamCreate` is available:

- **TeamCreate available** → use Team mode (Step 3A). Opus retains real conversation history between rounds — no context summarization needed.
- **TeamCreate not available** → use Subagent mode (Step 3B). A fresh Opus subagent is spawned each round with prior concerns injected.

---

## Step 3A: Team Mode

### Create the Opus teammate

```
TeamCreate:
  name: "opus-skeptic"
  model: "opus"
  system_prompt: |
    You are The Skeptic — a senior engineer who challenges plans by finding what
    everyone else missed. Focus on:
    1. Unstated assumptions — what is assumed true that could be false?
    2. Unhappy paths — what breaks when the first thing goes wrong?
    3. Second-order failures — what does a partial success leave behind?
    4. Security — is any user-controlled content reaching a shell string?
    5. The one fatal flaw — if this plan has one problem, what is it?

    Be specific, be direct, be constructive. End every response with exactly one of:
      VERDICT: APPROVED — plan is solid and ready to implement
      VERDICT: REVISE — concerns above should be addressed first
```

### Round loop (rounds 1–5)

**Round 1:** SendMessage to `opus-skeptic`:
```
Review this implementation plan (Round 1 of [MAX_ROUNDS]):

---
[CURRENT_PLAN]
---

Provide structured feedback with severity (CRITICAL / MAJOR / MINOR) for each concern.
```

**Rounds 2+:** SendMessage to `opus-skeptic` with the revision:
```
I've revised the plan based on your feedback. Here is what changed:

[REVISION_SUMMARY]

Updated plan:

---
[CURRENT_PLAN]
---

Re-review. Focus on whether prior concerns were addressed and any new issues introduced.
```

After each SendMessage, go to **Step 4** to check the verdict.

### Cleanup

Always call `TeamDelete` for `opus-skeptic` when done (approved, max rounds, or interrupted).

---

## Step 3B: Subagent Mode

Each round spawns a fresh Opus subagent via the Task tool:

```
Task:
  subagent_type: general-purpose
  model: opus
  prompt: |
    You are The Skeptic — a senior engineer who challenges plans by finding what
    everyone else missed. Focus on:
    1. Unstated assumptions — what is assumed true that could be false?
    2. Unhappy paths — what breaks when the first thing goes wrong?
    3. Second-order failures — what does a partial success leave behind?
    4. Security — is any user-controlled content reaching a shell string?
    5. The one fatal flaw — if this plan has one problem, what is it?

    [If Round > 1:]
    Prior concerns (Round [PREV_ROUND]):
    [PREV_CONCERNS — bullet summary, max 200 words]

    The plan has been revised. Focus on whether prior concerns were addressed
    and any new issues introduced.
    [End if]

    Review this implementation plan (Round [ROUND] of [MAX_ROUNDS]):

    ---
    [CURRENT_PLAN]
    ---

    Provide structured feedback with severity (CRITICAL / MAJOR / MINOR) for each concern.

    End with exactly one of:
      VERDICT: APPROVED — plan is solid and ready to implement
      VERDICT: REVISE — concerns above should be addressed first
```

After the subagent responds, go to **Step 4**.

After each REVISE round, save key concerns as `PREV_CONCERNS` (bullet summary, max 200 words) before incrementing `ROUND`.

---

## Step 4: Present the Review & Check Verdict

Display the review:

```
---
## Opus Review — Round [ROUND]

[review text]
```

Then check the verdict:

- **`VERDICT: APPROVED`** → go to **Step 6** (Done)
- **`VERDICT: REVISE`** and `ROUND >= MAX_ROUNDS` → go to **Step 6** with max-rounds note
- **`VERDICT: REVISE`** and `ROUND < MAX_ROUNDS` → go to **Step 5** (Revise)
- No clear verdict but feedback is all positive / no actionable items → treat as approved

---

## Step 5: Revise the Plan

1. **Revise `CURRENT_PLAN`** — address each concern Opus raised. Make real improvements, not cosmetic changes. If a revision would contradict the user's explicit requirements, skip it and note why.

2. **Show the user what changed:**
```
### Revisions (Round [ROUND])
- [What changed and why, one bullet per concern addressed]
```

3. Set `REVISION_SUMMARY` to the bullet list above. Increment `ROUND`. Go to **Step 3A** or **Step 3B** (whichever mode is active).

---

## Step 6: Final Result

**If approved:**
```
## Opus Review — Final

✅ Approved after [ROUND] round(s).

[Final Opus message]

---
## Final Plan

[CURRENT_PLAN]
```

**If max rounds reached without approval:**
```
## Opus Review — Final

⚠️ Max rounds ([MAX_ROUNDS]) reached — not fully approved.

Remaining concerns:
[Last round's unresolved issues]

---
## Final Plan

[CURRENT_PLAN]
```

Then clean up (TeamDelete if team mode was used).

---

## Rules

- Claude **actively revises the plan** between rounds — not just passing messages
- Team mode is preferred: real conversation continuity, no context truncation
- Subagent mode is the fallback: inject `PREV_CONCERNS` to bridge round context
- Max 5 rounds
- Show each round's feedback and revisions so the user can follow along
- Never interpolate AI-generated text directly into shell strings
