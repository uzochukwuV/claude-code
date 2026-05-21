---
description: "Configure an AI provider (Anthropic, OpenAI, Google, or custom)"
argument-hint: "<provider> [api_key] [endpoint]"
allowed-tools: ["Bash"]
---

# Configure Provider Command

Configure an AI provider with API key and optional endpoint.

```bash
#!/bin/bash
set -euo pipefail

CLOUD_AI_ROOT="${CLOUD_AI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CONFIG_FILE="${CLOUD_AI_ROOT}/config/provider-config.json"

PROVIDER="${1:-}"
API_KEY="${2:-}"
ENDPOINT="${3:-}"

if [[ -z "$PROVIDER" ]]; then
  echo "❌ Provider name required"
  echo ""
  echo "Usage: /configure-provider <provider> [api_key] [endpoint]"
  echo ""
  echo "Providers:"
  echo "  anthropic    - Anthropic Claude models"
  echo "  openai       - OpenAI GPT models"
  echo "  google       - Google Gemini models"
  echo "  custom       - Any OpenAI-compatible API"
  echo ""
  echo "Examples:"
  echo "  /configure-provider anthropic sk-ant-..."
  echo "  /configure-provider openai sk-..."
  echo "  /configure-provider custom your-key http://localhost:11434/v1"
  exit 1
fi

# Validate provider exists
if ! jq -e ".providers.${PROVIDER}" "$CONFIG_FILE" >/dev/null; then
  echo "❌ Unknown provider: $PROVIDER"
  echo "Available providers: $(jq -r '.providers | keys | join(", ")' "$CONFIG_FILE")"
  exit 1
fi

echo "🔧 Configuring $PROVIDER provider..."

# Enable the provider
TEMP_FILE="${CONFIG_FILE}.tmp"
jq ".providers.${PROVIDER}.enabled = true" "$CONFIG_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$CONFIG_FILE"

# Set API key if provided
if [[ -n "$API_KEY" ]]; then
  ENV_VAR=$(jq -r ".providers.${PROVIDER}.env_var" "$CONFIG_FILE")
  export "$ENV_VAR=$API_KEY"
  echo "✅ Set $ENV_VAR"
fi

# Set endpoint if provided (for custom provider)
if [[ -n "$ENDPOINT" ]]; then
  TEMP_FILE="${CONFIG_FILE}.tmp"
  jq ".providers.${PROVIDER}.api_endpoint = \"$ENDPOINT\"" "$CONFIG_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$CONFIG_FILE"
  echo "✅ Set endpoint: $ENDPOINT"
fi

# Switch to this provider as default
TEMP_FILE="${CONFIG_FILE}.tmp"
jq ".default_provider = \"$PROVIDER\"" "$CONFIG_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$CONFIG_FILE"
echo "✅ Set $PROVIDER as default provider"

echo ""
echo "✅ Provider configured successfully!"
echo ""
echo "Test the configuration:"
echo "  /cloud-status"
```

Usage examples:
- `/configure-provider anthropic sk-ant-api-key` - Configure Anthropic
- `/configure-provider openai sk-openai-key` - Configure OpenAI
- `/configure-provider google gemini-api-key` - Configure Google
- `/configure-provider custom ollama http://localhost:11434/v1` - Configure custom endpoint
