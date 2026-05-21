#!/bin/bash

# Cloud AI Session Start Hook
# Initializes environment variables and validates configuration on session start

set -euo pipefail

CLOUD_AI_ROOT="${CLOUD_AI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CONFIG_FILE="${CLOUD_AI_ROOT}/config/provider-config.json"

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "⚠️  Cloud AI config not found. Run /configure-provider first." >&2
  exit 0
fi

# Load default provider into environment
DEFAULT_PROVIDER=$(jq -r '.default_provider // "anthropic"' "$CONFIG_FILE")
ENV_VAR=$(jq -r ".providers.${DEFAULT_PROVIDER}.env_var // empty" "$CONFIG_FILE")

if [[ -n "$ENV_VAR" ]] && [[ -n "${!ENV_VAR:-}" ]]; then
  export CURRENT_AI_PROVIDER="$DEFAULT_PROVIDER"
fi

# Load default runtime
DEFAULT_RUNTIME=$(jq -r '.runtime.default // "docker"' "$CONFIG_FILE")
export CLOUD_AI_DEFAULT_RUNTIME="$DEFAULT_RUNTIME"

# Silent initialization - just set up environment
exit 0
