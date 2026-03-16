---
description: Check OpenRouter API connectivity, list available models, validate debate-openrouter.json config, and print permission allowlist for unattended operation.
allowed-tools: Bash(curl -s:*), Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(jq:*), Bash(which:*), Bash(ls:*), Bash(chmod:*), Write(~/.claude/debate-openrouter.json)
---

# debate — OpenRouter Setup Check

Verify OpenRouter prerequisites and print everything needed for `/debate:openrouter-review`.

---

## Step 1: Check tools

```bash
which curl
which jq
```

Report:
```text
## debate — OpenRouter Setup Check

### Tools
  ✅ curl    found at /path/to/curl
  ✅ jq      found at /path/to/jq
```

Both are required. If missing:
- `curl`: should be pre-installed on macOS/Linux
- `jq`: `brew install jq` (macOS) / `apt install jq` (Linux)

## Step 2: Check config file

Read `~/.claude/debate-openrouter.json`.

### If config exists

Show the parsed config:
```text
### Config: ~/.claude/debate-openrouter.json
  Base URL:  https://openrouter.ai/api/v1
  API Key:   [set] / [not set]
  Reviewers: gpt (openai/gpt-5.4-pro), mercury (inception/mercury-2), ...
```

If the config file contains an `api_key` field (inline key rather than env var reference), secure it:
```bash
chmod 600 ~/.claude/debate-openrouter.json
```

Proceed to Step 3.

### If config is missing — Interactive Setup

Guide the user through creating a config interactively:

**2a. API Key:**

Ask the user: "Do you have an OpenRouter API key? Paste it, or set `OPENROUTER_API_KEY` in your environment."

- If they paste a key: use `api_key` field, `chmod 600` after writing.
- If they say it's in an env var: use `"api_key_env": "OPENROUTER_API_KEY"`.

**2b. Fetch available models:**

Use the API key to fetch models from OpenRouter:

```bash
curl -s --max-time 15 -H "Authorization: Bearer $API_KEY" https://openrouter.ai/api/v1/models
```

Sort models by recency (`.created` field descending), filter out free-tier models (IDs ending in `:free`), and present the **top 15 newest** models as a numbered list:

```text
### Newest models on OpenRouter:
  1. x-ai/grok-4.20-beta
  2. openai/gpt-5.4-pro
  3. openai/gpt-5.4
  4. inception/mercury-2
  5. google/gemini-3.1-pro-preview
  6. moonshotai/kimi-k2.5
  ...
```

**2c. Ask the user to pick 2-4 reviewers:**

"Pick 2-4 models for your review panel (by number or model ID). The value of OpenRouter reviewers is getting perspectives from **models you don't already have** — if you're running this inside Claude, skip Anthropic models."

**2d. For each selected model, ask for a short reviewer name** (used in output filenames and CLI args). Suggest defaults based on the provider name (e.g., `gpt`, `mercury`, `kimi`, `gemini`).

**2e. Write the config:**

Write `~/.claude/debate-openrouter.json` with the selected reviewers:

```json
{
  "base_url": "https://openrouter.ai/api/v1",
  "api_key": "<key or omit>",
  "api_key_env": "<env var name or omit>",
  "headers": {
    "HTTP-Referer": "https://github.com/anthropics/claude-code",
    "X-Title": "cc-debate"
  },
  "reviewers": {
    "<name1>": { "model": "<model_id>", "timeout": 300 },
    "<name2>": { "model": "<model_id>", "timeout": 120 }
  }
}
```

Set timeout to 300 for larger models, 120 for smaller/faster ones.

If `api_key` is set inline: `chmod 600 ~/.claude/debate-openrouter.json`

---

## Step 3: Check OpenRouter connectivity

Read the API key from the config — either the `api_key` field or the env var named in `api_key_env`. Also extract any `headers` from config.

```bash
curl -s --max-time 10 -H "Authorization: Bearer $API_KEY" https://openrouter.ai/api/v1/models | jq -r '.data[0].id' 2>/dev/null
```

Report:
- Got a model ID back → `✅ OpenRouter API reachable`
- Error or empty → `❌ OpenRouter unreachable — check API key / network`

## Step 4: List available models

Parse the `/models` response and list model IDs from `.data[].id`, sorted by `.created` descending, top 20:

```text
### Available Models (via OpenRouter, newest first)
  - x-ai/grok-4.20-beta
  - openai/gpt-5.4-pro
  - inception/mercury-2
  - ...
```

## Step 5: Validate reviewer config against available models

For each reviewer in the config, check if its `model` value is an exact string match against `.data[].id` from the `/models` response:

```text
### Reviewer Model Validation
  ✅ gpt:     openai/gpt-5.4-pro     (available)
  ✅ mercury:  inception/mercury-2     (available)
  ❌ kimi:    moonshotai/kimi-k2.5    (NOT found on OpenRouter — check model ID)
```

## Step 6: Test API call (optional quick probe)

For each configured reviewer, make a minimal chat completion request to verify the model actually responds:

```bash
curl -s --max-time 30 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"model":"<model>","messages":[{"role":"user","content":"Reply with only the word PONG."}],"max_tokens":10}' \
  https://openrouter.ai/api/v1/chat/completions
```

Include any configured `headers` (HTTP-Referer, X-Title) in the request.

Report:
- Response contains content → `✅ <name>: <model> responds`
- Error/timeout → `❌ <name>: <model> failed — <error message>`

## Step 7: Check debate-scripts symlink

```bash
ls -la ~/.claude/debate-scripts/invoke-openai-compat.sh
```

Report:
- Found → `✅ invoke-openai-compat.sh accessible via debate-scripts symlink`
- Not found → `❌ Run /debate:setup first to create the symlink, then re-check`

## Step 8: Print permission allowlist

```text
### Permission Allowlist

To run /debate:openrouter-review without approval prompts, add to ~/.claude/settings.json:
```

```json
{
  "permissions": {
    "allow": [
      "Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*)",
      "Bash(bash ~/.claude/debate-scripts/run-parallel-openai-compat.sh:*)",
      "Bash(bash ~/.claude/debate-scripts/invoke-openai-compat.sh:*)",
      "Bash(curl -s:*)",
      "Bash(rm -rf .claude/tmp/ai-review-:*)",
      "Read(.claude/tmp/ai-review*)",
      "Edit(.claude/tmp/ai-review*)",
      "Write(.claude/tmp/ai-review*)"
    ]
  }
}
```

## Step 9: Print summary

```text
### Summary

  OpenRouter: ✅ reachable (https://openrouter.ai/api/v1)
  Config:     ✅ valid (N reviewers)
  curl:       ✅ ready
  jq:         ✅ ready
  Scripts:    ✅ symlinked

  Reviewers:
    <name1>   ✅ <model1>   (<timeout>s timeout)
    <name2>   ✅ <model2>   (<timeout>s timeout)

You are ready to run:
  /debate:openrouter-review              — parallel review via OpenRouter
  /debate:openrouter-review gpt,mercury  — specific reviewers only
```

If anything is missing, list remaining actions.
