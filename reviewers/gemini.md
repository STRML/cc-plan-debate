---
name: gemini
binary: gemini
display_name: Google Gemini
default_model: gemini-3.1-pro-preview
install_command: npm install -g @google/gemini-cli
---

# Gemini Reviewer Definition

**The Architect** — systems architect reviewing for structural integrity.

Focus areas: approach validity, over-engineering, missing phases, graceful degradation, alternatives.

## Availability Check

```bash
which gemini
```

## Invocation

All Gemini calls go through `scripts/invoke-gemini.sh`. The script handles:
- Model flags (`-m $MODEL -s -e ""`)
- Plan passed via stdin redirect (`< plan.md`)
- Session UUID capture via `--list-sessions` diff (before/after with 5s timeout guard)
- Resume with fallback to fresh call on failure

```bash
TIMEOUT_BIN="$TIMEOUT_BIN" bash "$SCRIPT_DIR/invoke-gemini.sh" \
  "$WORK_DIR" [session_uuid] [model]
```

## Prompt Files

- **Initial review:** no prompt file needed — script uses hardcoded Architect persona
- **Resume/debate:** write prompt to `$WORK_DIR/gemini-prompt.txt` before calling script

## Output Files

| File | Contents |
|------|----------|
| `gemini-output.md` | Review text |
| `gemini-session-id.txt` | Session UUID for next resume (empty on failure) |
| `gemini-exit.txt` | Exit code |
