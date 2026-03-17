---
description: Check acpx CLI installation, validate debate-acpx.json config, probe each configured agent, and print permission allowlist for unattended operation.
allowed-tools: Bash(which acpx:*), Bash(which npx:*), Bash(which jq:*), Bash(acpx:*), Bash(npx acpx@latest:*), Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(ls:*), Bash(chmod:*), Write(~/.claude/debate-acpx.json)
---

# debate — acpx Setup Check

Verify acpx prerequisites and print everything needed for `/debate:all`.

---

## Step 1: Check tools and set ACPX_CMD

```bash
which acpx || which npx
which jq
```

Determine the acpx invocation command:
- If `acpx` is found: set `ACPX_CMD=acpx`
- If `acpx` is not found but `npx` is: set `ACPX_CMD="npx acpx@latest"`
- If neither: stop with error

Report:
```text
## debate — acpx Setup Check

### Tools
  ✅ acpx   found at /path/to/acpx (using: acpx)
  ✅ jq     found at /path/to/jq
```

If `acpx` is not found but `npx` is:
```text
  ⚠️  acpx not installed globally — using: npx acpx@latest (slower first run)
     Install globally: npm install -g acpx@latest
```

If neither `acpx` nor `npx`:
```text
  ❌ acpx not found. Install: npm install -g acpx@latest
```

Both `acpx` (or `npx`) and `jq` are required. Use `ACPX_CMD` for all subsequent acpx invocations in this command.

## Step 2: Check config file

Read `~/.claude/debate-acpx.json`.

### If config exists

Show the parsed config:
```text
### Config: ~/.claude/debate-acpx.json
  Reviewers:
    codex   → agent: codex    (120s timeout)
    gemini  → agent: gemini   (240s timeout)
    kimi    → agent: kimi     (120s timeout)
```

Proceed to Step 3.

### If config is missing — Interactive Setup

Guide the user through creating a config:

**2a. List available acpx agents:**

```text
### Built-in acpx agents:
  codex    — OpenAI Codex CLI
  claude   — Claude Code
  gemini   — Google Gemini CLI
  cursor   — Cursor CLI
  copilot  — GitHub Copilot CLI
  kimi     — Kimi CLI
  kiro     — Kiro CLI
  qwen     — Qwen Code
  opencode — OpenCode
  kilocode — Kilocode
```

**2b. Ask the user to pick 2-4 agents:**

"Pick 2-4 agents for your review panel. The value is getting perspectives from different AI models. If you're running this inside Claude, skip the `claude` agent."

**2c. Write the config:**

Write `~/.claude/debate-acpx.json`:

```json
{
  "reviewers": {
    "<name1>": { "agent": "<agent>", "timeout": 120 },
    "<name2>": { "agent": "<agent>", "timeout": 240 }
  }
}
```

Set timeout to 240-300 for larger/slower agents, 120 for faster ones.

---

## Step 3: Probe each agent

For each configured reviewer, run a quick test:

```bash
echo "Reply with only the word PONG." | $ACPX_CMD --format quiet --approve-reads --timeout 30 <agent>
```

Report:
- Response contains "PONG" → `✅ <name>: <agent> responds`
- Error/timeout → `❌ <name>: <agent> failed — check that the agent CLI is installed`

## Step 4: Check debate-scripts symlink

```bash
ls -la ~/.claude/debate-scripts/invoke-acpx.sh
```

Report:
- Found → `✅ invoke-acpx.sh accessible via debate-scripts symlink`
- Not found → `❌ Run /debate:setup first to refresh the symlink`

## Step 5: Print permission allowlist

```text
### Permission Allowlist

To run /debate:all without approval prompts, add to ~/.claude/settings.json:
```

```json
{
  "permissions": {
    "allow": [
      "Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*)",
      "Bash(bash ~/.claude/debate-scripts/run-parallel-acpx.sh:*)",
      "Bash(bash ~/.claude/debate-scripts/invoke-acpx.sh:*)",
      "Bash(rm -rf .tmp/ai-review-:*)",
      "Read(.tmp/ai-review*)",
      "Edit(.tmp/ai-review*)",
      "Write(.tmp/ai-review*)"
    ]
  }
}
```

## Step 6: Print summary

```text
### Summary

  acpx:    ✅ ready
  Config:  ✅ valid (N reviewers)
  jq:      ✅ ready
  Scripts: ✅ symlinked

  Reviewers:
    <name1>  ✅ <agent1>   (<timeout>s timeout)
    <name2>  ✅ <agent2>   (<timeout>s timeout)

You are ready to run:
  /debate:all                     — parallel review via acpx
  /debate:all codex,gemini        — specific reviewers only
```

If anything is missing, list remaining actions.
