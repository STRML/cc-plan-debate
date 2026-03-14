---
description: Check OpenRouter API connectivity, list available models, validate debate-openrouter.json config, and print permission allowlist for unattended operation.
allowed-tools: Bash(curl -s:*), Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(jq:*), Bash(which:*), Bash(ls:*), Bash(chmod:*)
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

Read `~/.claude/debate-openrouter.json`. Report:

- File exists → show the parsed config:
  ```text
  ### Config: ~/.claude/debate-openrouter.json
    Base URL:  https://openrouter.ai/api/v1
    API Key:   [set] / [not set]
    Reviewers: claude (anthropic/claude-opus-4-6), deepseek (deepseek/deepseek-chat-v3-0324), ...
  ```
- File missing → show how to create it:
  ```text
  ❌ Config not found: ~/.claude/debate-openrouter.json

  Create it with this template:
  {
    "base_url": "https://openrouter.ai/api/v1",
    "api_key_env": "OPENROUTER_API_KEY",
    "headers": {
      "HTTP-Referer": "https://github.com/anthropics/claude-code",
      "X-Title": "cc-debate"
    },
    "reviewers": {
      "claude": {
        "model": "anthropic/claude-opus-4-6",
        "timeout": 300
      },
      "deepseek": {
        "model": "deepseek/deepseek-chat-v3-0324",
        "timeout": 120
      }
    }
  }
  ```

If the config file contains an `api_key` field (inline key rather than env var reference), secure it:
```bash
chmod 600 ~/.claude/debate-openrouter.json
```

## Step 3: Check OpenRouter connectivity

Extract `api_key_env` from config (default: `OPENROUTER_API_KEY`) and read the API key from that environment variable. Also extract any `headers` from config.

```bash
curl -s --max-time 10 -H "Authorization: Bearer $API_KEY" https://openrouter.ai/api/v1/models | jq -r '.data[0].id' 2>/dev/null
```

Report:
- Got a model ID back → `✅ OpenRouter API reachable`
- Error or empty → `❌ OpenRouter unreachable — check API key / network`

## Step 4: List available models

Parse the `/models` response and list all model IDs from `.data[].id`:

```text
### Available Models (via OpenRouter)
  - anthropic/claude-opus-4-6
  - deepseek/deepseek-chat-v3-0324
  - google/gemini-2.5-pro
  - ...
```

## Step 5: Validate reviewer config against available models

For each reviewer in the config, check if its `model` value is an exact string match against `.data[].id` from the `/models` response:

```text
### Reviewer Model Validation
  ✅ claude:   anthropic/claude-opus-4-6          (available)
  ✅ deepseek: deepseek/deepseek-chat-v3-0324     (available)
  ❌ gemini:   google/gemini-2.5-pro              (NOT found on OpenRouter — check model ID)
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
      "Bash(rm -rf /private/tmp/claude/ai-review-:*)",
      "Read(/private/tmp/claude/ai-review*)",
      "Edit(/private/tmp/claude/ai-review*)",
      "Write(/private/tmp/claude/ai-review*)"
    ]
  }
}
```

## Step 9: Print summary

```text
### Summary

  OpenRouter: ✅ reachable (https://openrouter.ai/api/v1)
  Config:     ✅ valid (2 reviewers)
  curl:       ✅ ready
  jq:         ✅ ready
  Scripts:    ✅ symlinked

  Reviewers:
    claude    ✅ anthropic/claude-opus-4-6          (300s timeout)
    deepseek  ✅ deepseek/deepseek-chat-v3-0324     (120s timeout)

You are ready to run:
  /debate:openrouter-review                — parallel review via OpenRouter
  /debate:openrouter-review claude,deepseek — specific reviewers only
```

If anything is missing, list remaining actions.
