# Migrating to debate v2.0.0

v2.0.0 replaces all provider-specific CLIs (codex, gemini, claude) and API-based providers (LiteLLM, OpenRouter) with a single unified approach via [acpx](https://github.com/openclaw/acpx).

## What changed

### Removed commands

| Old command | Replacement |
|-------------|-------------|
| `/debate:codex-review` | `/debate:all codex` |
| `/debate:gemini-review` | `/debate:all gemini` |
| `/debate:litellm-review` | `/debate:all` |
| `/debate:openrouter-review` | `/debate:all` |
| `/debate:litellm-setup` | `/debate:acpx-setup` |
| `/debate:openrouter-setup` | `/debate:acpx-setup` |

### Kept commands (updated)

| Command | What changed |
|---------|-------------|
| `/debate:all` | Now config-driven via `debate-acpx.json`. Shell mode removed. No more persona fallback. |
| `/debate:opus-review` | Now uses `acpx claude` instead of direct `claude` CLI. No more `jq` dependency. |
| `/debate:opus-review-subagent` | Unchanged — uses Task tool, no external process. |
| `/debate:setup` | Simplified — checks for `acpx` and `jq` only. |

### New commands

| Command | Purpose |
|---------|---------|
| `/debate:acpx-setup` | Interactive config creation + agent probing |

### Other changes

- Work directory moved from `.claude/tmp/ai-review-*` to `.tmp/ai-review-*`
- `reviewers/` directory removed — personas are now in `debate-acpx.json` config
- `shell-mode` argument removed from `/debate:all`
- Version bumped to 2.0.0

## New dependency: acpx

```bash
npm install -g acpx@latest
```

acpx is a headless CLI that communicates with coding agents via the Agent Client Protocol. It replaces direct CLI invocations (codex, gemini, claude) and API-based calls (curl to LiteLLM/OpenRouter).

The underlying agent CLIs (codex, gemini, etc.) still need to be installed — acpx communicates with them, it doesn't replace them.

## Migrating your config

### From LiteLLM (`~/.claude/debate-litellm.json`)

**Before:**
```json
{
  "base_url": "http://localhost:8200/v1",
  "api_key_env": "LITELLM_API_KEY",
  "reviewers": {
    "opus": {
      "model": "claude-opus-4-6",
      "timeout": 300,
      "system_prompt": "You are The Skeptic..."
    },
    "deepseek": {
      "model": "deepseek.v3-v1:0",
      "timeout": 120,
      "system_prompt": "You are The Pragmatist..."
    }
  }
}
```

**After** (`~/.claude/debate-acpx.json`):

LiteLLM routed API calls to arbitrary models. With acpx, each reviewer maps to an **agent** (a coding CLI), not a model. If you were using LiteLLM to access models that have a corresponding acpx agent, map them directly:

```json
{
  "reviewers": {
    "opus": {
      "agent": "claude",
      "timeout": 300,
      "system_prompt": "You are The Skeptic..."
    },
    "codex": {
      "agent": "codex",
      "timeout": 120,
      "system_prompt": "You are The Pragmatist..."
    }
  }
}
```

If you were using LiteLLM to access models that **don't** have an acpx agent (e.g., DeepSeek, Mixtral), those models are not currently supported. acpx only supports agents with a CLI binary. Check the [available agents](#available-acpx-agents) list.

### From OpenRouter (`~/.claude/debate-openrouter.json`)

Same approach as LiteLLM — map each reviewer to the corresponding acpx agent:

**Before:**
```json
{
  "base_url": "https://openrouter.ai/api/v1",
  "api_key_env": "OPENROUTER_API_KEY",
  "headers": { "HTTP-Referer": "...", "X-Title": "cc-debate" },
  "reviewers": {
    "gpt": { "model": "openai/gpt-5.4-pro", "timeout": 300 },
    "gemini": { "model": "google/gemini-2.5-pro", "timeout": 240 }
  }
}
```

**After:**
```json
{
  "reviewers": {
    "codex": { "agent": "codex", "timeout": 300 },
    "gemini": { "agent": "gemini", "timeout": 240 }
  }
}
```

No more `base_url`, `api_key`, or `headers` — acpx handles auth per-agent.

### From CLI mode (codex/gemini/opus direct)

If you were using `/debate:all` in CLI mode, the migration is just creating the config file. The old system auto-detected installed CLIs; the new system requires explicit configuration:

```bash
/debate:acpx-setup
```

This will walk you through selecting agents and creating `~/.claude/debate-acpx.json`.

## Migrating your settings.json

If you have permission allowlists in `~/.claude/settings.json`, update them:

**Remove** (old patterns):
```json
"Bash(bash ~/.claude/debate-scripts/run-parallel.sh:*)",
"Bash(bash ~/.claude/debate-scripts/invoke-codex.sh:*)",
"Bash(bash ~/.claude/debate-scripts/invoke-gemini.sh:*)",
"Bash(bash ~/.claude/debate-scripts/invoke-opus.sh:*)",
"Bash(bash ~/.claude/debate-scripts/invoke-openai-compat.sh:*)",
"Bash(bash ~/.claude/debate-scripts/run-parallel-openai-compat.sh:*)",
"Read(.claude/tmp/ai-review*)",
"Edit(.claude/tmp/ai-review*)",
"Write(.claude/tmp/ai-review*)",
"Bash(rm -rf .claude/tmp/ai-review-:*)"
```

**Add** (new patterns):
```json
"Bash(bash ~/.claude/debate-scripts/run-parallel-acpx.sh:*)",
"Bash(bash ~/.claude/debate-scripts/invoke-acpx.sh:*)",
"Read(.tmp/ai-review*)",
"Edit(.tmp/ai-review*)",
"Write(.tmp/ai-review*)",
"Bash(rm -rf .tmp/ai-review-:*)"
```

Run `/debate:setup` to get the complete updated allowlist.

## Refreshing the symlink

After updating the plugin, re-run `/debate:setup` to refresh the `~/.claude/debate-scripts` symlink. This ensures it points to the new scripts (`invoke-acpx.sh`, `run-parallel-acpx.sh`).

## Available acpx agents

| Agent | Wraps | Install |
|-------|-------|---------|
| `codex` | OpenAI Codex CLI | `npm install -g @openai/codex` |
| `claude` | Claude Code | Already installed |
| `gemini` | Google Gemini CLI | `npm install -g @google/gemini-cli` |
| `cursor` | Cursor CLI | Install Cursor IDE |
| `copilot` | GitHub Copilot CLI | `gh extension install github/gh-copilot` |
| `kimi` | Kimi CLI | See kimi docs |
| `kiro` | Kiro CLI | See kiro docs |
| `qwen` | Qwen Code | See qwen docs |
| `opencode` | OpenCode | `npx opencode-ai` |
| `kilocode` | Kilocode | `npx @kilocode/cli` |

See [acpx docs](https://github.com/openclaw/acpx) for the full and up-to-date list.
