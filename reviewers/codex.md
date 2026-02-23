---
name: codex
binary: codex
display_name: OpenAI Codex
default_model: gpt-5.3-codex
install_command: npm install -g @openai/codex
---

# Codex Reviewer Definition

**The Executor** — pragmatic runtime tracer focused on what will actually happen at runtime.

Focus areas: shell correctness, exit code handling, race conditions, file I/O, command availability.

## Availability Check

```bash
which codex
```

## Invocation

All Codex calls go through `scripts/invoke-codex.sh`. The script handles:
- Model flags (`-m $MODEL -s read-only`)
- Session resume with fallback to fresh call on failure
- Session ID extraction from stdout (`session id: UUID`)
- `PIPESTATUS[0]` exit code capture through tee pipeline

```bash
TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-codex.sh" \
  "$WORK_DIR" [session_id] [model]
```

## Prompt Files

- **Initial review:** no prompt file needed — script uses hardcoded Executor persona referencing `$WORK_DIR/plan.md`
- **Resume/debate:** write prompt to `$WORK_DIR/codex-prompt.txt` before calling script

## Output Files

| File | Contents |
|------|----------|
| `codex-output.md` | Review text |
| `codex-session-id.txt` | Session ID for next resume (empty on failure) |
| `codex-exit.txt` | Exit code |
| `codex-stdout.txt` | Raw stdout (used internally for session ID extraction) |
