#!/bin/bash

# Anthropic AI Provider Implementation
# Handles API communication with Anthropic's Claude models

set -euo pipefail

# Load configuration
PROVIDER_CONFIG="${CLOUD_AI_ROOT}/config/provider-config.json"

# Get API key from environment
get_api_key() {
  local api_key="${ANTHROPIC_API_KEY:-}"
  if [[ -z "$api_key" ]]; then
    echo "❌ Error: ANTHROPIC_API_KEY environment variable not set" >&2
    exit 1
  fi
  echo "$api_key"
}

# Get model from configuration or default
get_model() {
  local model="${1:-}"
  if [[ -z "$model" ]]; then
    model=$(jq -r '.providers.anthropic.models.default' "$PROVIDER_CONFIG")
  fi
  echo "$model"
}

# Send completion request to Anthropic API
# Usage: anthropic_complete "prompt" [model] [max_tokens] [temperature]
anthropic_complete() {
  local prompt="$1"
  local model="${2:-$(get_model)}"
  local max_tokens="${3:-4096}"
  local temperature="${4:-0.7}"
  
  local api_key
  api_key=$(get_api_key)
  
  local response
  response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $api_key" \
    -H "anthropic-version: 2023-06-01" \
    -d "{
      \"model\": \"$model\",
      \"max_tokens\": $max_tokens,
      \"temperature\": $temperature,
      \"messages\": [
        {
          \"role\": \"user\",
          \"content\": \"$prompt\"
        }
      ]
    }")
  
  # Extract content from response
  echo "$response" | jq -r '.content[0].text // empty'
}

# Stream completion request (for long-running tasks)
anthropic_stream() {
  local prompt="$1"
  local model="${2:-$(get_model)}"
  
  local api_key
  api_key=$(get_api_key)
  
  curl -s -X POST "https://api.anthropic.com/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $api_key" \
    -H "anthropic-version: 2023-06-01" \
    -d "{
      \"model\": \"$model\",
      \"max_tokens\": 4096,
      \"stream\": true,
      \"messages\": [
        {
          \"role\": \"user\",
          \"content\": \"$prompt\"
        }
      ]
    }"
}

# Validate API key
validate_api_key() {
  local api_key
  api_key=$(get_api_key)
  
  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" \
    -X GET "https://api.anthropic.com/v1/models" \
    -H "x-api-key: $api_key" \
    -H "anthropic-version: 2023-06-01")
  
  if [[ "$response" == "200" ]]; then
    echo "✅ Anthropic API key is valid"
    return 0
  else
    echo "❌ Anthropic API key validation failed (HTTP $response)"
    return 1
  fi
}

# List available models
list_models() {
  local api_key
  api_key=$(get_api_key)
  
  curl -s "https://api.anthropic.com/v1/models" \
    -H "x-api-key: $api_key" \
    -H "anthropic-version: 2023-06-01" | jq '.data[] | {id, name, created_at}'
}

# Main command handler
case "${1:-help}" in
  complete)
    shift
    anthropic_complete "$@"
    ;;
  stream)
    shift
    anthropic_stream "$@"
    ;;
  validate)
    validate_api_key
    ;;
  models)
    list_models
    ;;
  help|*)
    cat << 'HELP_EOF'
Anthropic AI Provider

USAGE:
  anthropic-provider <command> [arguments]

COMMANDS:
  complete <prompt> [model] [max_tokens] [temperature]
    Send a completion request to Anthropic API
    
  stream <prompt> [model]
    Stream a completion request (useful for long responses)
    
  validate
    Validate the configured API key
    
  models
    List available Anthropic models
    
  help
    Show this help message

ENVIRONMENT VARIABLES:
  ANTHROPIC_API_KEY    Required. Your Anthropic API key

EXAMPLES:
  anthropic-provider complete "Write a hello world function"
  anthropic-provider complete "Analyze this code" claude-opus-4-5-20250929 8192
  anthropic-provider validate
  anthropic-provider models
HELP_EOF
    ;;
esac
