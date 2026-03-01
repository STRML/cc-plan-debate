---
description: Quick single-round Opus plan review using Claude's built-in Task tool (subagent). No CLI subprocess, no session management, no file I/O — just fast feedback. Use /debate:opus-review for iterative multi-round review.
allowed-tools: "Task(subagent_type: general-purpose)"
---

# Quick Opus Plan Review (Subagent)

Launch an Opus subagent directly via the Task tool to review the current plan. Single round — fast sanity check with no subprocess overhead.

Unlike `/debate:opus-review` which spawns an external `claude` CLI process with full session management, this command uses Claude's built-in Task tool. No temp files, no jq, no exit codes to check.

Opus plays the role of **The Skeptic** — a devil's advocate focused on unstated assumptions, unhappy paths, second-order failures, and security.

---

## Step 1: Capture the Plan

If there is no plan in the current context, ask the user what they want reviewed.

## Step 2: Launch Subagent Review

Use the Task tool with:
- `subagent_type`: `"general-purpose"`
- `model`: `"opus"`
- `prompt`: The Skeptic review prompt with the full plan embedded

Use this prompt (substitute the actual plan content for `[PLAN]`):

```
You are The Skeptic — a senior engineer who challenges plans by focusing on:
- Unstated assumptions that could fail at runtime
- Unhappy paths and error cases the plan glosses over
- Second-order failures (what happens when the fix itself fails?)
- Security vulnerabilities or data exposure risks
- Over-engineering or missing simplifications

Review this implementation plan:

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
## Opus Subagent Review

[response]
```

Check the verdict:
- `VERDICT: APPROVED` → "Opus approved the plan."
- `VERDICT: REVISE` → present the concerns and ask the user how to proceed

## Rules

- Single round only — no iteration. For iterative review use `/debate:opus-review`
- For full parallel multi-model review use `/debate:all`
- This command has no bash calls and no temp files — it's fully self-contained
