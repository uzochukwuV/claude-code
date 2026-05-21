#!/bin/bash

# OpenAI AI Provider Implementation
# Handles API communication with OpenAI's GPT models

set -euo pipefail

# Load configuration
PROVIDER_CONFIG="${CLOUD_AI_ROOT}/config/provider-config.json"

# Get API key from environment
get_api_key() {
  local api_key="${OPENAI_API_KEY:-}"
  if [[ -z "$api_key" ]]; then
    echo "❌ Error: OPENAI_API_KEY environment variable not set" >&2
    exit 1
  fi
  echo "$api_key"
}

# Get model from configuration or default
get_model() {
  local model="${1:-}"
  if [[ -z "$model" ]]; then
    model=$(jq -r '.providers.openai.models.default' "$PROVIDER_CONFIG")
  fi
  echo "$model"
}

# Send completion request to OpenAI API
# Usage: openai_complete "prompt" [model] [max_tokens] [temperature]
openai_complete() {
  local prompt="$1"
  local model="${2:-$(get_model)}"
  local max_tokens="${3:-4096}"
  local temperature="${4:-0.7}"
  
  local api_key
  api_key=$(get_api_key)
  
  local response
  response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $api_key" \
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
  echo "$response" | jq -r '.choices[0].message.content // empty'
}

# Stream completion request (for long-running tasks)
openai_stream() {
  local prompt="$1"
  local model="${2:-$(get_model)}"
  
  local api_key
  api_key=$(get_api_key)
  
  curl -s -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $api_key" \
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
    -X GET "https://api.openai.com/v1/models" \
    -H "Authorization: Bearer $api_key")
  
  if [[ "$response" == "200" ]]; then
    echo "✅ OpenAI API key is valid"
    return 0
  else
    echo "❌ OpenAI API key validation failed (HTTP $response)"
    return 1
  fi
}

# List available models
list_models() {
  local api_key
  api_key=$(get_api_key)
  
  curl -s "https://api.openai.com/v1/models" \
    -H "Authorization: Bearer $api_key" | jq '.data[] | {id, created, owned_by}'
}

# Main command handler
case "${1:-help}" in
  complete)
    shift
    openai_complete "$@"
    ;;
  stream)
    shift
    openai_stream "$@"
    ;;
  validate)
    validate_api_key
    ;;
  models)
    list_models
    ;;
  help|*)
    cat << 'HELP_EOF'
OpenAI Provider

USAGE:
  openai-provider <command> [arguments]

COMMANDS:
  complete <prompt> [model] [max_tokens] [temperature]
    Send a completion request to OpenAI API
    
  stream <prompt> [model]
    Stream a completion request (useful for long responses)
    
  validate
    Validate the configured API key
    
  models
    List available OpenAI models
    
  help
    Show this help message

ENVIRONMENT VARIABLES:
  OPENAI_API_KEY    Required. Your OpenAI API key

EXAMPLES:
  openai-provider complete "Write a hello world function"
  openai-provider complete "Analyze this code" gpt-4o 8192
  openai-provider validate
  openai-provider models
HELP_EOF
    ;;
esac
