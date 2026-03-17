---
description: Check acpx CLI installation, validate debate-acpx.json config, probe each configured agent, and print permission allowlist for unattended operation.
allowed-tools: Bash(which acpx:*), Bash(which npx:*), Bash(which jq:*), Bash(which opencode:*), Bash(acpx:*), Bash(npx acpx@latest:*), Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(ls:*), Bash(chmod:*), Bash(mkdir:*), Write(~/.claude/debate-acpx.json), Write(~/.acpx/*), Write(~/.opencode.json)
---

# debate — acpx Setup Check

Verify acpx prerequisites and print everything needed for `/debate:all`.

---

## Step 1: Check tools and set ACPX_CMD

```bash
which acpx || which npx
which jq
which opencode
```

Determine the acpx invocation command:
- If `acpx` is found: set `ACPX_CMD=acpx`
- If `acpx` is not found but `npx` is: set `ACPX_CMD="npx acpx@latest"`
- If neither: stop with error

Report:
```text
## debate — acpx Setup Check

### Tools
  ✅ acpx      found at /path/to/acpx (using: acpx)
  ✅ jq        found at /path/to/jq
  ✅ opencode  found at /path/to/opencode (enables OpenRouter models)
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

Note whether `opencode` is available — it's needed for OpenRouter model access (Step 2c).

Both `acpx` (or `npx`) and `jq` are required. Use `ACPX_CMD` for all subsequent acpx invocations in this command.

## Step 2: Check config file

Read `~/.claude/debate-acpx.json`.

### If config exists

Show the parsed config:
```text
### Config: ~/.claude/debate-acpx.json
  Reviewers:
    codex    → agent: codex    (built-in, 120s timeout)
    gemini   → agent: gemini   (built-in, 240s timeout)
    mercury  → agent: mercury  (custom/opencode, 120s timeout)
```

Proceed to Step 3.

### If config is missing — Interactive Setup

Guide the user through creating a config.

**2a. Ask what agents the user wants:**

Present two categories:

```text
### Reviewer options

Built-in acpx agents (need the agent CLI installed):
  codex    — OpenAI Codex        (npm install -g @openai/codex)
  claude   — Claude Code         (already installed)
  gemini   — Google Gemini       (npm install -g @google/gemini-cli)
  cursor   — Cursor CLI          (install Cursor IDE)
  copilot  — GitHub Copilot CLI  (gh extension install github/gh-copilot)
  kimi     — Kimi CLI
  kiro     — Kiro CLI
  qwen     — Qwen Code
  opencode — OpenCode            (npm install -g opencode-ai)

OpenRouter models via opencode (need opencode + OpenRouter API key):
  Any model on OpenRouter — DeepSeek, Mercury, Kimi, Mixtral, GPT, etc.
  These run through: acpx → opencode → OpenRouter → model
```

"Pick 2-4 reviewers. For independent perspectives inside Claude, skip the `claude` agent. If you want models from OpenRouter, I'll set those up via opencode."

**2b. For each selected reviewer, determine the type:**
- If the user picks a built-in acpx agent name → type: `built-in`
- If the user picks an OpenRouter model (or a model name that isn't a built-in agent) → type: `openrouter`

**2c. For OpenRouter reviewers — set up opencode wrappers:**

This requires `opencode` to be installed. If not found:
```text
  ❌ opencode not installed. OpenRouter models require it.
     Install: npm install -g opencode-ai
     Then re-run /debate:acpx-setup
```

For each OpenRouter reviewer, ask for:
1. A short name (e.g., `mercury`, `deepseek`)
2. The OpenRouter model ID (e.g., `inception/mercury-2`, `deepseek/deepseek-r1`)

Then ask for the user's OpenRouter API key (or check if `OPENROUTER_API_KEY` env var is set).

For each OpenRouter reviewer, create a wrapper script and per-agent opencode config:

```bash
mkdir -p ~/.acpx/agents/<name>
```

Write `~/.acpx/agents/<name>/.opencode.json`:
```json
{
  "provider": {
    "openrouter": {
      "apiKey": "<OPENROUTER_API_KEY>"
    }
  },
  "agents": {
    "coder": {
      "model": "openrouter/<model_id>"
    }
  }
}
```

Write `~/.acpx/agents/<name>/start.sh`:
```bash
#!/bin/bash
export OPENCODE_CONFIG_CONTENT='{"model":"openrouter/<model_id>"}'
exec opencode acp "$@"
```

```bash
chmod +x ~/.acpx/agents/<name>/start.sh
chmod 600 ~/.acpx/agents/<name>/.opencode.json
```

Register the custom agent in `~/.acpx/config.json`. Read the existing config first, merge the new agent, and write back:
```json
{
  "agents": {
    "<name>": {
      "command": "/Users/<user>/.acpx/agents/<name>/start.sh"
    }
  }
}
```

Use absolute paths in the command field — acpx exec's the command directly.

**2d. Write the debate config:**

Write `~/.claude/debate-acpx.json` with all selected reviewers:

```json
{
  "reviewers": {
    "codex": { "agent": "codex", "timeout": 120, "system_prompt": "..." },
    "mercury": { "agent": "mercury", "timeout": 120, "system_prompt": "..." }
  }
}
```

Set timeout to 240-300 for larger/slower agents, 120 for faster ones.

For system prompts, suggest unique review personas for each reviewer. Examples:
- **The Executor** — shell correctness, exit codes, race conditions, file I/O
- **The Architect** — structural integrity, over-engineering, missing phases, graceful degradation
- **The Skeptic** — unstated assumptions, unhappy paths, second-order failures, security
- **The Contrarian** — questions conventional wisdom, hidden assumptions, scaling bottlenecks
- **The Pragmatist** — what will actually ship, unnecessary complexity, missing happy path steps

---

## Step 3: Probe each agent

For each configured reviewer, run a quick test:

```bash
echo "Reply with only the word PONG." | $ACPX_CMD --format quiet --approve-reads --timeout 30 <agent>
```

Note: for custom agents (OpenRouter via opencode), this will create an acpx session. If the probe fails with "No acpx session found", first create one:
```bash
$ACPX_CMD <agent> sessions new
```
Then retry the probe.

Report:
- Response contains "PONG" → `✅ <name>: <agent> responds`
- Error/timeout → `❌ <name>: <agent> failed — check that the agent CLI is installed and authenticated`

For OpenRouter agents, a common failure mode is wrong model ID. Suggest the user verify the model ID at openrouter.ai/models.

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

  acpx:     ✅ ready
  opencode: ✅ ready (enables OpenRouter models)
  Config:   ✅ valid (N reviewers)
  jq:       ✅ ready
  Scripts:  ✅ symlinked

  Reviewers:
    codex    ✅ built-in    (120s timeout)
    gemini   ✅ built-in    (240s timeout)
    mercury  ✅ openrouter  (120s timeout, inception/mercury-2)

You are ready to run:
  /debate:all                     — parallel review via acpx
  /debate:all codex,mercury       — specific reviewers only
```

If anything is missing, list remaining actions.
