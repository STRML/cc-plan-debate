# OpenRouter Support Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OpenRouter as a reviewer provider by generalizing the LiteLLM scripts to be provider-agnostic.

**Architecture:** Rename `invoke-litellm.sh` → `invoke-openai-compat.sh` and `run-parallel-litellm.sh` → `run-parallel-openai-compat.sh`, parameterized by config file path. Add backward-compat symlinks. Create new OpenRouter commands mirroring LiteLLM commands. Update existing LiteLLM commands to use new script names.

**Tech Stack:** Bash, jq, curl (OpenAI-compatible chat completions API)

**Spec:** `docs/superpowers/specs/2026-03-14-openrouter-support-design.md`

**Note:** This project has no test suite. Verification is via `bash -n` (syntax check) and manual invocation.

---

## Chunk 1: Generic Scripts

### Task 1: Rename and generalize `invoke-litellm.sh` → `invoke-openai-compat.sh`

**Files:**
- Create: `scripts/invoke-openai-compat.sh` (from `scripts/invoke-litellm.sh`)
- Delete: `scripts/invoke-litellm.sh`

- [ ] **Step 1: Create `invoke-openai-compat.sh`**

Copy `scripts/invoke-litellm.sh` to `scripts/invoke-openai-compat.sh` via `git mv`, then apply these changes:

1. Update header comment — new name, new signature, new config description:
```bash
#!/bin/bash
# Generic reviewer invocation via any OpenAI-compatible API.
# Stateless — no session resume. Each call sends full context.
#
# Usage: invoke-openai-compat.sh <config_file> <work_dir> <reviewer_name> [model] [timeout]
#   config_file   — path to JSON config (e.g. ~/.claude/debate-litellm.json)
#   work_dir      — temp directory (must contain plan.md)
#   reviewer_name — e.g. "deepseek", "gemini", "opus"
#   model         — optional override; falls back to config value
#   timeout       — optional override; falls back to config value, then 120s
```

2. Shift positional args — add `CONFIG_FILE` as arg 1:
```bash
CONFIG_FILE="${1:-}"
WORK_DIR="${2:-}"
REVIEWER="${3:-}"
MODEL_ARG="${4:-}"
TIMEOUT_ARG="${5:-}"

if [ -z "$CONFIG_FILE" ] || [ -z "$WORK_DIR" ] || [ -z "$REVIEWER" ]; then
  echo "Usage: $0 <config_file> <work_dir> <reviewer_name> [model] [timeout]" >&2
  exit 1
fi
```

3. Hard-fail on missing config (replace the old soft fallback at lines 83-92):
```bash
if [ ! -f "$CONFIG_FILE" ]; then
  echo "invoke-openai-compat: config not found: $CONFIG_FILE" >&2
  exit 1
fi

BASE_URL=$(jq -r '.base_url // empty' "$CONFIG_FILE")
if [ -z "$BASE_URL" ]; then
  echo "invoke-openai-compat: base_url is required in $CONFIG_FILE" >&2
  exit 1
fi
BASE_URL="${BASE_URL%/}"
API_KEY=$(jq -r '.api_key // ""' "$CONFIG_FILE")
CONFIG_MODEL=$(jq -r --arg rev "$REVIEWER" '.reviewers[$rev].model // empty' "$CONFIG_FILE")
CONFIG_TIMEOUT=$(jq -r --arg rev "$REVIEWER" '.reviewers[$rev].timeout // empty' "$CONFIG_FILE")
CONFIG_SYSTEM_PROMPT=$(jq -r --arg rev "$REVIEWER" '.reviewers[$rev].system_prompt // empty' "$CONFIG_FILE")
```

4. Replace the `LITELLM_API_KEY` hardcoded fallback (line 106) with `api_key_env` + deprecation warning:
```bash
# API key: config api_key > config api_key_env > deprecation check > empty
if [ -z "$API_KEY" ]; then
  API_KEY_ENV=$(jq -r '.api_key_env // empty' "$CONFIG_FILE")
  if [ -n "$API_KEY_ENV" ]; then
    API_KEY="${!API_KEY_ENV:-}"
  fi
fi

if [ -z "$API_KEY" ] && [ -n "${LITELLM_API_KEY:-}" ]; then
  echo "WARNING: LITELLM_API_KEY is set but not referenced in config." >&2
  echo "  Add \"api_key_env\": \"LITELLM_API_KEY\" to $CONFIG_FILE" >&2
fi
```

5. Add headers support — after building `CURL_ARGS` (after line 170), before appending payload:
```bash
# --- Extra headers from config ---
HEADER_KEYS=$(jq -r '.headers // {} | keys[]' "$CONFIG_FILE" 2>/dev/null) || true
while IFS= read -r hkey; do
  [ -z "$hkey" ] && continue
  hval=$(jq -r --arg k "$hkey" '.headers[$k]' "$CONFIG_FILE")
  # Reject \r, \n, null bytes
  if [[ "$hkey" == *$'\r'* ]] || [[ "$hkey" == *$'\n'* ]] || [[ "$hkey" == *$'\0'* ]]; then
    echo "invoke-openai-compat: invalid header key containing control chars: '$hkey'" >&2
    exit 1
  fi
  if [[ "$hval" == *$'\r'* ]] || [[ "$hval" == *$'\n'* ]] || [[ "$hval" == *$'\0'* ]]; then
    echo "invoke-openai-compat: invalid header value for '$hkey' containing control chars" >&2
    exit 1
  fi
  CURL_ARGS+=(-H "$hkey: $hval")
done <<< "$HEADER_KEYS"
```

6. Replace all `invoke-litellm.sh` and `LiteLLM` references in log/error messages with generic equivalents:
   - `"invoke-litellm.sh:"` → `"invoke-openai-compat:"`
   - `"via LiteLLM"` → `"via $BASE_URL"`

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/invoke-openai-compat.sh`
Expected: no output (clean parse)

- [ ] **Step 3: Commit**

```
git add scripts/invoke-openai-compat.sh
git rm scripts/invoke-litellm.sh
git commit -m "refactor: rename invoke-litellm.sh to invoke-openai-compat.sh

Generalize to accept config_file as first arg. Add api_key_env
support, header injection with validation, LITELLM_API_KEY
deprecation warning. Hard-fail on missing config."
```

---

### Task 2: Rename and generalize `run-parallel-litellm.sh` → `run-parallel-openai-compat.sh`

**Files:**
- Create: `scripts/run-parallel-openai-compat.sh` (from `scripts/run-parallel-litellm.sh`)
- Delete: `scripts/run-parallel-litellm.sh`

- [ ] **Step 1: Create `run-parallel-openai-compat.sh`**

`git mv scripts/run-parallel-litellm.sh scripts/run-parallel-openai-compat.sh`, then apply:

1. Update header comment:
```bash
#!/bin/bash
# Parallel runner for OpenAI-compatible API debate reviews.
# Reads reviewer list from config, spawns invoke-openai-compat.sh
# for each, and polls for completion.
#
# Usage: run-parallel-openai-compat.sh <config_file> <REVIEW_ID> [reviewer1,reviewer2,...]
#   config_file — path to JSON config
#   REVIEW_ID   — 8-char hex ID (work dir: .claude/tmp/ai-review-<ID>)
#   reviewers   — optional comma-separated list; defaults to all from config
```

2. Shift positional args:
```bash
CONFIG_FILE="${1:-}"
REVIEW_ID="${2:-}"
REVIEWER_LIST="${3:-}"

if [ -z "$CONFIG_FILE" ] || [ -z "$REVIEW_ID" ]; then
  echo "Usage: $0 <config_file> <REVIEW_ID> [reviewer1,reviewer2,...]" >&2
  exit 1
fi
```

3. Remove hardcoded config path (line 25) — it's now from arg.

4. Update config-not-found error (lines 35-39):
```bash
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config not found: $CONFIG_FILE" >&2
  exit 1
fi
```

5. Replace `mapfile` (line 45) with bash 3.2-compatible loop:
```bash
  REVIEWERS=()
  while IFS= read -r line; do
    REVIEWERS+=("$line")
  done < <(jq -r '.reviewers | keys[]' "$CONFIG_FILE")
```

6. Update the `nohup` call (line 66-67) to pass config file:
```bash
  nohup bash "$SCRIPT_DIR/invoke-openai-compat.sh" "$CONFIG_FILE" "$WORK_DIR" "$NAME" "$MODEL" "$TIMEOUT" \
    > /dev/null 2>&1 &
```

7. Replace all `litellm` references in log messages with generic.

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/run-parallel-openai-compat.sh`
Expected: no output

- [ ] **Step 3: Commit**

```
git add scripts/run-parallel-openai-compat.sh
git rm scripts/run-parallel-litellm.sh
git commit -m "refactor: rename run-parallel-litellm.sh to run-parallel-openai-compat.sh

Accept config_file as first arg, pass through to invoke script.
Fix mapfile bash 3.2 compat. Generic log messages."
```

---

### Task 3: Add backward-compat symlinks in `create-links.sh`

**Files:**
- Modify: `scripts/create-links.sh:9-11`

- [ ] **Step 1: Add symlink creation after the main symlink succeeds**

After line 11 (`echo "   Re-run /debate:setup..."`) and before `else`, add:
```bash
  # Backward-compat symlinks for old script names (settings.json allowlists)
  ln -sf invoke-openai-compat.sh "$SELF_DIR/invoke-litellm.sh" 2>/dev/null || true
  ln -sf run-parallel-openai-compat.sh "$SELF_DIR/run-parallel-litellm.sh" 2>/dev/null || true
```

Note: These are created inside the scripts dir itself (`$SELF_DIR`), so when the main symlink (`~/.claude/debate-scripts`) resolves, the compat symlinks are visible at `~/.claude/debate-scripts/invoke-litellm.sh`.

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/create-links.sh`
Expected: no output

- [ ] **Step 3: Commit**

```
git add scripts/create-links.sh
git commit -m "feat: add backward-compat symlinks for renamed litellm scripts"
```

---

## Chunk 2: Update Existing LiteLLM Commands

### Task 4: Update `litellm-review.md`

**Files:**
- Modify: `commands/litellm-review.md`

- [ ] **Step 1: Update `allowed-tools` frontmatter**

Change line 3 from:
```
allowed-tools: Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(bash ~/.claude/debate-scripts/run-parallel-litellm.sh:*), Bash(bash ~/.claude/debate-scripts/invoke-litellm.sh:*), Bash(curl -s:*), Bash(rm -rf .claude/tmp/ai-review-:*), Write(.claude/tmp/ai-review-*)
```
To:
```
allowed-tools: Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(bash ~/.claude/debate-scripts/run-parallel-openai-compat.sh:*), Bash(bash ~/.claude/debate-scripts/invoke-openai-compat.sh:*), Bash(curl -s:*), Bash(rm -rf .claude/tmp/ai-review-:*), Write(.claude/tmp/ai-review-*)
```

- [ ] **Step 2: Update Step 2 parallel runner invocation**

Find the line:
```bash
bash "<SCRIPT_DIR>/run-parallel-litellm.sh" "<REVIEW_ID>" "<REVIEWER_LIST>"
```
Replace with:
```bash
bash "<SCRIPT_DIR>/run-parallel-openai-compat.sh" "~/.claude/debate-litellm.json" "<REVIEW_ID>" "<REVIEWER_LIST>"
```

- [ ] **Step 3: Update Step 5 direct invoke calls**

Find:
```bash
bash "<SCRIPT_DIR>/invoke-litellm.sh" "<WORK_DIR>" "<name>"
```
Replace with:
```bash
bash "<SCRIPT_DIR>/invoke-openai-compat.sh" "~/.claude/debate-litellm.json" "<WORK_DIR>" "<name>"
```

- [ ] **Step 4: Replace any remaining `invoke-litellm` or `run-parallel-litellm` references**

Search the file for any remaining `litellm.sh` script references and update them. Do NOT change the command name or user-facing text like "LiteLLM Review" — those stay.

- [ ] **Step 5: Commit**

```
git add commands/litellm-review.md
git commit -m "fix: update litellm-review to use renamed generic scripts

Pass ~/.claude/debate-litellm.json as config_file first arg."
```

---

### Task 5: Update `litellm-setup.md`

**Files:**
- Modify: `commands/litellm-setup.md`

- [ ] **Step 1: Update `allowed-tools` frontmatter**

Replace any `invoke-litellm.sh` or `run-parallel-litellm.sh` references with `invoke-openai-compat.sh` / `run-parallel-openai-compat.sh`.

- [ ] **Step 2: Update Step 7 symlink health check**

Find:
```bash
ls -la ~/.claude/debate-scripts/invoke-litellm.sh
```
Replace with:
```bash
ls -la ~/.claude/debate-scripts/invoke-openai-compat.sh
```

- [ ] **Step 3: Update config template to use `api_key_env`**

In the config template example, change from showing `"api_key": ""` to:
```json
{
  "base_url": "http://localhost:8200/v1",
  "api_key_env": "LITELLM_API_KEY",
  "reviewers": {
    "opus": {
      "model": "claude-opus-4-6",
      "timeout": 300,
      "system_prompt": "You are The Skeptic..."
    }
  }
}
```

- [ ] **Step 4: Add stale allowlist detection to Step 8**

After the existing permission allowlist printout, add:

```markdown
### Stale Allowlist Check

Check `~/.claude/settings.json` for old script names:

```bash
grep -l "invoke-litellm\|run-parallel-litellm" ~/.claude/settings.json 2>/dev/null
```

If found, warn:
```text
⚠️  Your settings.json contains old script names (invoke-litellm.sh / run-parallel-litellm.sh).
    Backward-compat symlinks are in place, so these still work.
    To update, replace with:
      invoke-openai-compat.sh
      run-parallel-openai-compat.sh
```
```

- [ ] **Step 5: Update permission allowlist to show new script names**

Replace `invoke-litellm.sh` → `invoke-openai-compat.sh` and `run-parallel-litellm.sh` → `run-parallel-openai-compat.sh` in the allowlist printout.

- [ ] **Step 6: Commit**

```
git add commands/litellm-setup.md
git commit -m "fix: update litellm-setup for renamed scripts

Use api_key_env in config template. Add stale allowlist detection.
Check for invoke-openai-compat.sh in symlink health check."
```

---

## Chunk 3: New OpenRouter Commands

### Task 6: Create `openrouter-review.md`

**Files:**
- Create: `commands/openrouter-review.md`

- [ ] **Step 1: Create the command file**

Copy `commands/litellm-review.md` as the starting point, then apply these changes:

1. **Frontmatter** — update description and allowed-tools:
```yaml
---
description: Run AI reviewers in parallel via OpenRouter, synthesize feedback, debate contradictions, and produce a consensus verdict. Supports any model available through OpenRouter. Configure reviewers in ~/.claude/debate-openrouter.json.
allowed-tools: Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(bash ~/.claude/debate-scripts/run-parallel-openai-compat.sh:*), Bash(bash ~/.claude/debate-scripts/invoke-openai-compat.sh:*), Bash(curl -s:*), Bash(rm -rf .claude/tmp/ai-review-:*), Write(.claude/tmp/ai-review-*)
---
```

2. **Title**: `# AI Multi-Model Plan Review (OpenRouter)`

3. **Step 1a**: Change config path from `~/.claude/debate-litellm.json` to `~/.claude/debate-openrouter.json`. Change setup reference from `/debate:litellm-setup` to `/debate:openrouter-setup`.

4. **Step 1b**: Remove the LiteLLM connectivity probe (Step 1b in litellm-review checks proxy reachability). OpenRouter is a hosted service — skip this entirely.

5. **Step 1d announce block**: Change header to "OpenRouter Review" and show `https://openrouter.ai/api/v1`.

6. **All script invocations**: Use `"~/.claude/debate-openrouter.json"` as config arg:
   - Step 2: `bash "<SCRIPT_DIR>/run-parallel-openai-compat.sh" "~/.claude/debate-openrouter.json" "<REVIEW_ID>" "<REVIEWER_LIST>"`
   - Step 5: `bash "<SCRIPT_DIR>/invoke-openai-compat.sh" "~/.claude/debate-openrouter.json" "<WORK_DIR>" "<name>"`

7. **All user-facing text**: Replace "LiteLLM" with "OpenRouter" in headings and output format.

- [ ] **Step 2: Commit**

```
git add commands/openrouter-review.md
git commit -m "feat: add /debate:openrouter-review command

Mirrors litellm-review with OpenRouter config and no proxy check."
```

---

### Task 7: Create `openrouter-setup.md`

**Files:**
- Create: `commands/openrouter-setup.md`

- [ ] **Step 1: Create the command file**

Copy `commands/litellm-setup.md` as starting point, then apply:

1. **Frontmatter** — update description:
```yaml
---
description: Check OpenRouter API connectivity, list available models, validate debate-openrouter.json config, and print permission allowlist for unattended operation.
allowed-tools: Bash(curl -s:*), Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(jq:*), Bash(which:*), Bash(ls:*), Bash(chmod:*)
---
```

2. **Title**: `# debate — OpenRouter Setup Check`

3. **Step 2 (config check)**: Change path to `~/.claude/debate-openrouter.json`. Update the missing-config template to:
```json
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

Add after config creation: `chmod 600 ~/.claude/debate-openrouter.json`

4. **Step 3 (connectivity)**: Replace local proxy check with OpenRouter API check:
```bash
curl -s --max-time 10 -H "Authorization: Bearer $API_KEY" https://openrouter.ai/api/v1/models | jq -r '.data[0].id' 2>/dev/null
```
Report: got a model ID → reachable. Error → check API key.

5. **Step 4 (list models)**: Parse `.data[].id` from `/models` response.

6. **Step 5 (validate)**: Exact string match of each reviewer's model against `.data[].id`.

7. **Step 6 (test probe)**: Same pattern but use `https://openrouter.ai/api/v1/chat/completions` with auth header.

8. **Step 7 (symlink check)**: Check for `invoke-openai-compat.sh`.

9. **Step 8 (permission allowlist)**: Print allowlist with `invoke-openai-compat.sh` and `run-parallel-openai-compat.sh`.

10. **Step 9 (summary)**: Show OpenRouter-specific summary.

- [ ] **Step 2: Commit**

```
git add commands/openrouter-setup.md
git commit -m "feat: add /debate:openrouter-setup command

Validates OpenRouter API key, lists models, checks reviewer config."
```

---

## Chunk 4: Version Bump & Metadata

### Task 8: Bump version and update metadata

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Update `plugin.json`**

Change version from `"1.1.30"` to `"1.2.0"` (new feature = minor bump).
Update description to mention OpenRouter:
```json
"description": "Multi-model AI plan review: run Codex, Gemini, OpenRouter, and LiteLLM reviewers in parallel, synthesize feedback, debate contradictions"
```
Add `"openrouter"` and `"litellm"` to keywords:
```json
"keywords": ["review", "codex", "gemini", "ai", "plan-review", "multi-model", "debate", "openrouter", "litellm"]
```

- [ ] **Step 2: Update `marketplace.json`**

Change version from `"1.1.30"` to `"1.2.0"`.
Update description to mention OpenRouter:
```json
"description": "Multi-model AI plan review with parallel execution, synthesis, and debate — supports Codex, Gemini, OpenRouter, and LiteLLM"
```

- [ ] **Step 3: Commit**

```
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "chore: bump version to 1.2.0, add OpenRouter to metadata"
```

---

## Verification

After all tasks are complete, verify end-to-end:

- [ ] `bash -n scripts/invoke-openai-compat.sh` — clean parse
- [ ] `bash -n scripts/run-parallel-openai-compat.sh` — clean parse
- [ ] `bash -n scripts/create-links.sh` — clean parse
- [ ] `grep -r "invoke-litellm" commands/` — should only appear in user-facing text (not script paths), except litellm-review.md/litellm-setup.md user-facing mentions
- [ ] `grep -r "run-parallel-litellm" commands/` — same
- [ ] Verify `commands/openrouter-review.md` exists and references `debate-openrouter.json`
- [ ] Verify `commands/openrouter-setup.md` exists and references `debate-openrouter.json`
