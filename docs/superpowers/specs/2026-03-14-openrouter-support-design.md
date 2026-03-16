# OpenRouter Support via Generic OpenAI-Compatible Scripts

**Date:** 2026-03-14
**Status:** Draft

## Summary

Add OpenRouter as a reviewer provider alongside LiteLLM. Both use the OpenAI-compatible chat completions API, so we rename the LiteLLM-specific scripts to provider-agnostic versions and add new commands for OpenRouter. Existing LiteLLM users are unaffected — their config file and commands continue to work. Backward-compat symlinks ensure old script names keep working during the transition.

## Decisions

- **Generic scripts, not duplicated.** `invoke-litellm.sh` and `run-parallel-litellm.sh` become `invoke-openai-compat.sh` and `run-parallel-openai-compat.sh`. They accept a config file path as their first argument and know nothing about any specific provider.
- **Backward-compat symlinks.** `create-links.sh` creates `invoke-litellm.sh` → `invoke-openai-compat.sh` and `run-parallel-litellm.sh` → `run-parallel-openai-compat.sh` in the scripts directory. Old `settings.json` allowlist entries continue to match. These symlinks can be removed in a future major version.
- **One config file per provider.** `~/.claude/debate-litellm.json` and `~/.claude/debate-openrouter.json` share the same schema. No multi-provider config file.
- **OpenRouter stays separate from `/debate:all`.** It gets its own `/debate:openrouter-review` and `/debate:openrouter-setup` commands. `/debate:all` remains CLI-only (codex, gemini, opus).
- **Commands are the user interface.** Script renames are invisible to users — commands abstract the script paths.

## Config Schema (shared)

Both `debate-litellm.json` and `debate-openrouter.json` use this schema:

```json
{
  "base_url": "https://openrouter.ai/api/v1",
  "api_key_env": "OPENROUTER_API_KEY",
  "headers": {
    "HTTP-Referer": "https://github.com/anthropics/claude-code",
    "X-Title": "cc-debate"
  },
  "reviewers": {
    "<name>": {
      "model": "anthropic/claude-opus-4-6",
      "timeout": 300,
      "system_prompt": "..."
    }
  }
}
```

Fields:
- `base_url` (string, required): API endpoint. No default in the script — each config must specify it. Script exits with error if missing.
- `api_key` (string, optional): Bearer token. Checked first. **Not included in default templates** — prefer `api_key_env` to avoid committing secrets. Documented but secondary.
- `api_key_env` (string, optional): Name of env var to check if `api_key` is empty. E.g. `"OPENROUTER_API_KEY"` or `"LITELLM_API_KEY"`. Resolved via bash indirect expansion `${!var}` — **never use `eval`**.
- `headers` (object, optional): Extra HTTP headers added to every curl call. OpenRouter uses `HTTP-Referer` and `X-Title`. LiteLLM configs omit this.
- `reviewers` (object, required): Map of reviewer name to config.
  - `model` (string, required): Model identifier.
  - `timeout` (integer, optional): Request timeout in seconds. Default: 120.
  - `system_prompt` (string, optional): Custom system prompt. Default: built-in generic reviewer.

### API key resolution order

1. Config `api_key` field (if non-empty)
2. Env var named in config `api_key_env` field (if set) — resolved via `${!API_KEY_ENV}`, never `eval`
3. **Deprecation check:** If both `api_key` and `api_key_env` are empty/unset, and `$LITELLM_API_KEY` exists in the environment, emit a warning: `"WARNING: LITELLM_API_KEY is set but not referenced in config. Add \"api_key_env\": \"LITELLM_API_KEY\" to $CONFIG_FILE"`. Do NOT silently use it — this is a one-release grace period warning before the env var is fully ignored.
4. Empty (no auth header sent)

### Config file security

Setup commands (`litellm-setup`, `openrouter-setup`) should `chmod 600` the config file after creation if it contains an `api_key` field.

## Script Changes

### `invoke-openai-compat.sh` (renamed from `invoke-litellm.sh`)

**New signature:**
```
invoke-openai-compat.sh <config_file> <work_dir> <reviewer_name> [model] [timeout]
```

Changes from `invoke-litellm.sh`:
- First arg is now `config_file` path (was hardcoded to `~/.claude/debate-litellm.json`).
- **Hard-fail if config file doesn't exist:** `[ -f "$CONFIG_FILE" ] || { echo "config not found: $CONFIG_FILE" >&2; exit 1; }`. No soft fallback.
- API key resolution uses `api_key` → `api_key_env` (via `${!var}`) → deprecation warning for `LITELLM_API_KEY` → empty.
- Reads optional `headers` from config. Each header key/value is extracted individually via `jq -r` and validated: reject keys or values containing `\r`, `\n`, or null bytes (`\0`). On validation failure, **exit 1** with error message naming the offending header key. Valid headers are appended to the bash `CURL_ARGS` array as separate `-H` and `"key: value"` elements.
- All `litellm` references in log messages become generic (e.g. `"Submitting plan to $MODEL via $BASE_URL"`).
- No default for `base_url` — config must provide it (exit 1 if missing).

### `run-parallel-openai-compat.sh` (renamed from `run-parallel-litellm.sh`)

**New signature:**
```
run-parallel-openai-compat.sh <config_file> <REVIEW_ID> [reviewer1,reviewer2,...]
```

Changes from `run-parallel-litellm.sh`:
- First arg is `config_file` path.
- Internal `invoke-litellm.sh` call (line 66) becomes `invoke-openai-compat.sh`, with config file passed as first arg:
  ```bash
  nohup bash "$SCRIPT_DIR/invoke-openai-compat.sh" "$CONFIG_FILE" "$WORK_DIR" "$NAME" "$MODEL" "$TIMEOUT" \
      > /dev/null 2>&1 &
  ```
- Config-not-found error message references the config file path (generic, not provider-specific).
- All `litellm` references in log messages become generic.
- **Fix pre-existing `mapfile` issue:** Replace `mapfile -t REVIEWERS < <(jq ...)` with a bash 3.2-compatible alternative:
  ```bash
  while IFS= read -r line; do REVIEWERS+=("$line"); done < <(jq -r '.reviewers | keys[]' "$CONFIG_FILE")
  ```

### `create-links.sh` update

Add backward-compat symlinks for old script names:
```bash
ln -sf invoke-openai-compat.sh "$LINK_DIR/invoke-litellm.sh"
ln -sf run-parallel-openai-compat.sh "$LINK_DIR/run-parallel-litellm.sh"
```

These ensure existing `settings.json` permission allowlists referencing the old names continue to work. Can be removed in a future major version.

## New Commands

### `openrouter-review.md`

Mirrors `litellm-review.md` with these differences:
- Config file: `~/.claude/debate-openrouter.json`
- No connectivity probe (OpenRouter is a hosted service, not a local proxy)
- `allowed-tools` references `invoke-openai-compat.sh` and `run-parallel-openai-compat.sh`
- Announce block shows "OpenRouter Review" header and `https://openrouter.ai/api/v1`

**Step 2 invocation (parallel):**
```bash
bash "<SCRIPT_DIR>/run-parallel-openai-compat.sh" "~/.claude/debate-openrouter.json" "<REVIEW_ID>" "<REVIEWER_LIST>"
```

**Step 5 invocation (debate, per-reviewer):**
```bash
bash "<SCRIPT_DIR>/invoke-openai-compat.sh" "~/.claude/debate-openrouter.json" "<WORK_DIR>" "<name>"
```

### `openrouter-setup.md`

Mirrors `litellm-setup.md` with these differences:
- Config file: `~/.claude/debate-openrouter.json`
- No local proxy connectivity check
- Tests API key validity via OpenRouter's `/models` endpoint (parse `.data[].id` with jq)
- Validates each configured reviewer's model exists in `/models` response via exact string match on `.data[].id`
- Config template uses OpenRouter defaults — `api_key_env` only (no `api_key` in template), includes `headers`
- `chmod 600` on config file after creation
- Permission allowlist references the renamed scripts

## Updated Commands

### `litellm-review.md`

- Script references change from `invoke-litellm.sh` → `invoke-openai-compat.sh` and `run-parallel-litellm.sh` → `run-parallel-openai-compat.sh`
- `allowed-tools` updated to reference new script names
- User-facing behavior unchanged

**Updated Step 2 invocation (parallel):**
```bash
bash "<SCRIPT_DIR>/run-parallel-openai-compat.sh" "~/.claude/debate-litellm.json" "<REVIEW_ID>" "<REVIEWER_LIST>"
```

**Updated Step 5 invocation (debate, per-reviewer):**
```bash
bash "<SCRIPT_DIR>/invoke-openai-compat.sh" "~/.claude/debate-litellm.json" "<WORK_DIR>" "<name>"
```

### `litellm-setup.md`

- Script references updated
- Step 7 symlink health check changes from `invoke-litellm.sh` → `invoke-openai-compat.sh`
- Config template adds `"api_key_env": "LITELLM_API_KEY"` for backward compat
- Config template uses `api_key_env` only (no `api_key` in template)
- `chmod 600` on config file after creation
- Permission allowlist references renamed scripts
- **New: stale allowlist detection.** Step 8 checks if the user's `~/.claude/settings.json` contains old script names (`invoke-litellm.sh`, `run-parallel-litellm.sh`) and prints a warning with the updated allowlist entries to replace them.

## Files Changed

| File | Action |
|------|--------|
| `scripts/invoke-litellm.sh` | Rename → `scripts/invoke-openai-compat.sh`, generalize |
| `scripts/run-parallel-litellm.sh` | Rename → `scripts/run-parallel-openai-compat.sh`, generalize |
| `scripts/create-links.sh` | Add backward-compat symlinks for old script names |
| `commands/litellm-review.md` | Update script refs and invocation templates with config path arg |
| `commands/litellm-setup.md` | Update script refs, add stale allowlist detection, `api_key_env` template |
| `commands/openrouter-review.md` | **New** — OpenRouter review command |
| `commands/openrouter-setup.md` | **New** — OpenRouter setup command |
| `.claude-plugin/plugin.json` | Version bump |
| `.claude-plugin/marketplace.json` | Version bump, add OpenRouter to description and keywords |

## Files Not Changed

- `scripts/invoke-codex.sh`, `invoke-gemini.sh`, `invoke-opus.sh` — CLI reviewers, unrelated
- `scripts/run-parallel.sh` — CLI parallel runner, unrelated
- `scripts/debate-setup.sh`, `probe-model.sh` — shared utilities, no changes needed
- `commands/all.md` — CLI-only orchestrator, untouched (verified: no litellm references)
- `commands/codex-review.md`, `gemini-review.md`, `opus-review.md`, `opus-review-subagent.md` — single-reviewer commands, unrelated
- `commands/setup.md` — CLI prerequisites check, unrelated
- `reviewers/` — persona definitions, unrelated

## Migration

Existing LiteLLM users:
- `~/.claude/debate-litellm.json` continues to work as-is — the `api_key_env` field is optional.
- **`LITELLM_API_KEY` env var:** If you relied on this env var for auth (rather than setting `api_key` in the config), the script will now warn you to add `"api_key_env": "LITELLM_API_KEY"` to your config. Auth will NOT silently degrade — you'll see a clear warning. In a future version, this warning will be removed and the env var will be fully ignored.
- `/debate:litellm-review` and `/debate:litellm-setup` commands work identically.
- After plugin update, re-run `/debate:setup` to refresh the symlink. Backward-compat symlinks ensure old `settings.json` allowlist entries still work, but re-running `litellm-setup` will detect stale entries and print updated ones.

## Risks

- **OpenRouter rate limits:** OpenRouter has per-model rate limits that vary. The parallel runner spawning 3+ reviewers simultaneously might hit limits. Mitigation: timeouts and error messages already handle this gracefully.
- **Backward-compat symlink removal:** The old-name symlinks must be maintained until a major version bump. Document the removal timeline.
