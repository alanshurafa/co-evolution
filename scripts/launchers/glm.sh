#!/usr/bin/env bash
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  printf '%s\n' 'glm: run this launcher; do not source it into the caller shell.' >&2
  return 64
fi

set -euo pipefail

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd -P)"
repo_root="$(CDPATH= cd "$script_dir/../.." && pwd -P)"
env_file="$repo_root/.env.local"
zai_api_key="${ZAI_API_KEY-}"

if [[ -z "$zai_api_key" && -f "$env_file" ]]; then
  # Read only ZAI_API_KEY. Sourcing .env.local would execute arbitrary shell
  # syntax and export unrelated repository configuration.
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?ZAI_API_KEY[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      candidate="${BASH_REMATCH[2]}"
      candidate="${candidate%$'\r'}"
      candidate="${candidate#"${candidate%%[![:space:]]*}"}"
      candidate="${candidate%"${candidate##*[![:space:]]}"}"

      if (( ${#candidate} >= 2 )); then
        first="${candidate:0:1}"
        last="${candidate:${#candidate}-1:1}"
        if [[ ( "$first" == '"' && "$last" == '"' ) ||
              ( "$first" == "'" && "$last" == "'" ) ]]; then
          candidate="${candidate:1:${#candidate}-2}"
        fi
      fi

      zai_api_key="$candidate"
      break
    fi
  done < "$env_file"
fi

if [[ -z "$zai_api_key" ]]; then
  printf '%s\n' \
    'glm: ZAI_API_KEY is not set and was not found in the repository .env.local file.' >&2
  exit 78
fi

if [[ -z "${HOME-}" ]]; then
  printf '%s\n' 'glm: HOME is not set; cannot choose the isolated Claude config directory.' >&2
  exit 78
fi

claude_path="$(type -P claude || true)"
if [[ -z "$claude_path" ]]; then
  printf '%s\n' 'glm: Claude CLI was not found on PATH. Install Claude Code before using this launcher.' >&2
  exit 127
fi

# These assignments apply to the Claude child only; nothing is exported back
# into the caller shell and no Claude settings file is modified.
exec env \
  -u ANTHROPIC_API_KEY \
  -u ANTHROPIC_CUSTOM_HEADERS \
  -u CLAUDE_CODE_OAUTH_TOKEN \
  -u CLAUDE_CODE_USE_BEDROCK \
  -u CLAUDE_CODE_USE_VERTEX \
  -u CLAUDE_CODE_USE_FOUNDRY \
  ANTHROPIC_BASE_URL='https://api.z.ai/api/anthropic' \
  ANTHROPIC_AUTH_TOKEN="$zai_api_key" \
  CLAUDE_CONFIG_DIR="$HOME/.claude-glm" \
  "$claude_path" --safe-mode --model 'glm-5.3-flash' "$@"
