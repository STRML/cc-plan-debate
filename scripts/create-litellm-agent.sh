#!/bin/bash
# Create an acpx agent wrapper that routes through a LiteLLM proxy via opencode.
#
# Usage: create-litellm-agent.sh <name> <base_url> <model_alias> [api_key]
#
#   name         — short agent name (e.g. deepseek, mixtral, local-llama)
#   base_url     — LiteLLM proxy URL (e.g. http://localhost:8200/v1)
#   model_alias  — OpenAI model name opencode will use (e.g. gpt-4o-mini)
#                  Must be a model opencode knows under the OpenAI provider.
#                  LiteLLM must be configured to route this alias to your model.
#   api_key      — LiteLLM API key (optional; use "none" or omit if not required)
#
# Chain: acpx → opencode (custom agent) → LiteLLM proxy → any model
#
# After running this script:
#   1. Add the reviewer to ~/.claude/debate-acpx.json
#   2. Run /debate:acpx-setup to probe connectivity

set -euo pipefail

NAME="${1:-}"
BASE_URL="${2:-}"
MODEL_ALIAS="${3:-}"
API_KEY="${4:-none}"

if [ -z "$NAME" ] || [ -z "$BASE_URL" ] || [ -z "$MODEL_ALIAS" ]; then
  echo "Usage: $0 <name> <base_url> <model_alias> [api_key]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  $0 deepseek http://localhost:8200/v1 gpt-4o-mini sk-litellm-abc123" >&2
  echo "  $0 local-llama http://localhost:11434/v1 gpt-4o-mini" >&2
  echo "" >&2
  echo "The model_alias must be an OpenAI model name (e.g. gpt-4o-mini, gpt-4o)." >&2
  echo "LiteLLM should be configured to route that alias to your actual model." >&2
  exit 1
fi

# Resolve home directory without $() expansion
AGENT_DIR="${HOME}/.acpx/agents/${NAME}"

echo "Creating LiteLLM agent wrapper: ${NAME}" >&2
echo "  Base URL:     ${BASE_URL}" >&2
echo "  Model alias:  openai/${MODEL_ALIAS}" >&2
echo "  Agent dir:    ${AGENT_DIR}" >&2

mkdir -p "${AGENT_DIR}"

# Build start.sh — OPENCODE_CONFIG_CONTENT carries the full opencode config inline
# so no ~/.opencode.json is needed in the wrapper directory.
START_SH="${AGENT_DIR}/start.sh"

# Construct the JSON config. API key defaults to "none" if not provided.
if [ "$API_KEY" = "none" ] || [ -z "$API_KEY" ]; then
  OPENCODE_CONFIG='{"provider":{"openai":{"options":{"baseURL":"'"${BASE_URL}"'"}}},"model":"openai/'"${MODEL_ALIAS}"'"}'
else
  OPENCODE_CONFIG='{"provider":{"openai":{"options":{"baseURL":"'"${BASE_URL}"'","apiKey":"'"${API_KEY}"'"}}},"model":"openai/'"${MODEL_ALIAS}"'"}'
fi

cat > "${START_SH}" << STARTSH
#!/bin/bash
export OPENCODE_CONFIG_CONTENT='${OPENCODE_CONFIG}'
exec opencode acp "\$@"
STARTSH

chmod +x "${START_SH}"
echo "  Written:  ${START_SH}" >&2

# Register in ~/.acpx/config.json — read existing config, merge, write back
ACPX_CONFIG="${HOME}/.acpx/config.json"
ABSOLUTE_START="${AGENT_DIR}/start.sh"

if [ -f "${ACPX_CONFIG}" ]; then
  # Merge the new agent into existing config using jq
  if command -v jq > /dev/null 2>&1; then
    MERGED=$(jq --arg name "${NAME}" --arg cmd "${ABSOLUTE_START}" \
      '.agents[$name] = {"command": $cmd}' "${ACPX_CONFIG}")
    echo "${MERGED}" > "${ACPX_CONFIG}"
    echo "  Updated:  ${ACPX_CONFIG}" >&2
  else
    echo "  WARNING: jq not found — cannot update ${ACPX_CONFIG} automatically." >&2
    echo "  Manually add to ${ACPX_CONFIG}:" >&2
    echo "    { \"agents\": { \"${NAME}\": { \"command\": \"${ABSOLUTE_START}\" } } }" >&2
  fi
else
  mkdir -p "${HOME}/.acpx"
  printf '{\n  "agents": {\n    "%s": {\n      "command": "%s"\n    }\n  }\n}\n' \
    "${NAME}" "${ABSOLUTE_START}" > "${ACPX_CONFIG}"
  echo "  Created:  ${ACPX_CONFIG}" >&2
fi

echo "" >&2
echo "Agent '${NAME}' created. Next steps:" >&2
echo "" >&2
echo "  1. Add to ~/.claude/debate-acpx.json:" >&2
echo '     "'"${NAME}"'": {' >&2
echo '       "agent": "'"${NAME}"'",' >&2
echo '       "timeout": 120,' >&2
echo '       "model_id": "'"${MODEL_ALIAS}"' via LiteLLM",' >&2
echo '       "system_prompt": "You are ..."' >&2
echo '     }' >&2
echo "" >&2
echo "  2. Run /debate:acpx-setup to probe connectivity." >&2
