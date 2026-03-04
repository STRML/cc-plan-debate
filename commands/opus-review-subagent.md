---
description: Iterative Opus plan review using Claude's built-in Task tool (subagent). Claude and Opus go back-and-forth until Opus approves or max 5 rounds reached. No CLI subprocess, no session management.
allowed-tools: "Task(subagent_type: general-purpose)"
---

# Iterative Opus Plan Review (Subagent)

Launch an Opus subagent directly via the Task tool to review the current plan. Iterates up to 5 rounds — Opus reviews, you revise, Opus reviews again — until approved or max rounds reached.

Unlike `/debate:opus-review` which spawns an external `claude` CLI process with full session management, this command uses Claude's built-in Task tool. No temp files, no jq, no exit codes to check.

Opus plays the role of **The Skeptic** — a devil's advocate focused on unstated assumptions, unhappy paths, second-order failures, and security.

---

## Step 1: Capture the Plan

If there is no plan in the current context, ask the user what they want reviewed.

Set `CURRENT_PLAN` = the plan text. Set `ROUND = 1`. Set `MAX_ROUNDS = 5`.

## Step 2: Launch Subagent Review

Use the Task tool with:
- `subagent_type`: `"general-purpose"`
- `model`: `"opus"`
- `prompt`: The Skeptic review prompt with the full plan embedded

Use this prompt (substitute the actual plan content for `[PLAN]`, round number for `[ROUND]`, and previous review summary for `[PREV_CONTEXT]` — omit the Previous Context section on Round 1):

```
You are The Skeptic — a senior engineer who challenges plans by focusing on:
- Unstated assumptions that could fail at runtime
- Unhappy paths and error cases the plan glosses over
- Second-order failures (what happens when the fix itself fails?)
- Security vulnerabilities or data exposure risks
- Over-engineering or missing simplifications

[If Round > 1, include:]
Previous Context (Round [PREV_ROUND]):
[PREV_CONTEXT]

The plan has been revised. Focus on whether prior concerns were addressed and any new issues introduced.
[End if]

Review this implementation plan (Round [ROUND] of [MAX_ROUNDS]):

---
[PLAN]
---

Provide structured feedback:
1. List each concern with severity: CRITICAL / MAJOR / MINOR
2. For each concern, explain the failure mode specifically
3. Suggest a concrete mitigation

Be skeptical. Be specific. Be constructive.

End with exactly one of:
  VERDICT: APPROVED — plan is solid and ready to implement
  VERDICT: REVISE — concerns above should be addressed first
```

## Step 3: Present the Review

Display the subagent response:

```
---
## Opus Subagent Review — Round [ROUND]

[response]
```

## Step 4: Check Verdict and Iterate

- **`VERDICT: APPROVED`** → Print "Opus approved the plan after [ROUND] round(s)." Stop.

- **`VERDICT: REVISE`** and `ROUND >= MAX_ROUNDS` → Print "Max rounds ([MAX_ROUNDS]) reached without approval. Presenting final concerns to user." Stop.

- **`VERDICT: REVISE`** and `ROUND < MAX_ROUNDS`:
  1. Present the concerns clearly to the user
  2. Ask: "How would you like to address these concerns? Provide a revised plan or describe changes to make."
  3. Wait for the user's revised plan or change description
  4. If the user provides changes, apply them to `CURRENT_PLAN` (or incorporate their description as revision notes)
  5. Save the current round's key concerns as `PREV_CONTEXT` (bullet summary, max 200 words)
  6. Increment `ROUND`
  7. Go to **Step 2**

## Rules

- Maximum 5 rounds
- `PREV_CONTEXT` is a brief bullet summary of prior concerns — not the full review text
- For full parallel multi-model review use `/debate:all`
- This command has no bash calls and no temp files — it's fully self-contained
