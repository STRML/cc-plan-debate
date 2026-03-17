# Architecture — debate plugin
_Updated: 2026-03-17_

## Overview

`cc-debate` is a Claude Code plugin that sends implementation plans to multiple AI models for parallel review via [acpx](https://github.com/openclaw/acpx). It synthesizes feedback, resolves contradictions via targeted debate, and produces a consensus verdict before code is written.

## Top-level Layout

```
cc-debate/
├── .claude-plugin/         # Plugin metadata (marketplace.json, plugin.json)
├── commands/               # Claude Code slash commands (*.md skill files)
├── scripts/                # Shell scripts for reviewer invocation and orchestration
├── docs/plans/             # Historical design plans
└── README.md
```

## Execution Flow

```
/debate:all
    └── commands/all.md         # Master orchestrator
         ├── 1a. Read ~/.claude/debate-acpx.json
         ├── 1b. Generate REVIEW_ID, WORK_DIR via debate-setup.sh
         ├── 1c. Announce reviewers
         ├── 1d. Write plan.md to WORK_DIR
         ├── 1e. Detect EXEC_MODE (team / agent)
         │
         ├── Round N: Parallel review
         │    ├── team   → TeamCreate once + SendMessage for rounds 2+
         │    └── agent  → Agent tool with run_in_background: true
         │    Each reviewer agent calls invoke-acpx.sh → acpx <agent>
         │
         ├── Step 3: Read output files (<name>-output.md)
         ├── Step 4: Synthesize + check for APPROVED
         ├── Step 5: Debate (targeted per-reviewer questions)
         ├── Step 6: Final report + revision loop
         └── Step 9: Cleanup (rm WORK_DIR, TeamDelete)
```

## Two Execution Modes

| Mode | Trigger | Continuity | Concurrency |
|------|---------|-----------|-------------|
| `team` | `TeamCreate` tool available + succeeded | Real (teammates persist) | Parallel spawns round 1, SendMessage round 2+ |
| `agent` | `TeamCreate` unavailable or failed | Fake (context injection) | Parallel round 1, sequential later |

## Stable Symlink Pattern

`debate:setup` runs `scripts/create-links.sh`, creating `~/.claude/debate-scripts →` installed scripts dir.

All command files call `bash ~/.claude/debate-scripts/<script>.sh` — literal, stable path; no version in path, no runtime glob.

## acpx Agent Invocation

All reviewers are invoked through `acpx --format quiet --approve-reads <agent> --file <prompt>`. The `invoke-acpx.sh` script wraps this with timeout handling, config resolution, and output file management. Reviewer configuration (agent name, timeout, system prompt) is stored in `~/.claude/debate-acpx.json`.
