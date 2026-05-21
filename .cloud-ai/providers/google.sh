#!/bin/bash

# Google AI Provider Implementation
# Handles API communication with Google's Gemini models

set -euo pipefail

# Load configuration
PROVIDER_CONFIG="${CLOUD_AI_ROOT}/config/provider-config.json"

# Get API key from environment
get_api_key() {
  local api_key="${GOOGLE_API_KEY:-}"
  if [[ -z "$api_key" ]]; then
    echo "❌ Error: GOOGLE_API_KEY environment variable not set" >&2
    exit 1
  fi
  echo "$api_key"
}

# Get model from configuration or default
get_model() {
  local model="${1:-}"
  if [[ -z "$model" ]]; then
    model=$(jq -r '.providers.google.models.default' "$PROVIDER_CONFIG")
  fi
  echo "$model"
}

# Send completion request to Google Generative AI API
# Usage: google_complete "prompt" [model] [max_tokens] [temperature]
google_complete() {
  local prompt="$1"
  local model="${2:-$(get_model)}"
  local max_tokens="${3:-4096}"
  local temperature="${4:-0.7}"
  
  local api_key
  api_key=$(get_api_key)
  
  # Convert model name to API format (replace dashes with underscores for some models)
  local api_model="${model//-/_}"
  
  local response
  response=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/${api_model}:generateContent?key=${api_key}" \
    -H "Content-Type: application/json" \
    -d "{
      \"contents\": [
        {
          \"parts\": [
            {
              \"text\": \"$prompt\"
            }
          ]
        }
      ],
      \"generationConfig\": {
        \"maxOutputTokens\": $max_tokens,
        \"temperature\": $temperature
      }
    }")
  
  # Extract content from response
  echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty'
}

# Validate API key
validate_api_key() {
  local api_key
  api_key=$(get_api_key)
  
  # Try to list models as validation
  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" \
    -X GET "https://generativelanguage.googleapis.com/v1beta/models?key=${api_key}")
  
  if [[ "$response" == "200" ]]; then
    echo "✅ Google API key is valid"
    return 0
  else
    echo "❌ Google API key validation failed (HTTP $response)"
    return 1
  fi
}

# List available models
list_models() {
  local api_key
  api_key=$(get_api_key)
  
  curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=${api_key}" \
    | jq '.models[] | {name, displayName, description}'
}

# Main command handler
case "${1:-help}" in
  complete)
    shift
    google_complete "$@"
    ;;
  validate)
    validate_api_key
    ;;
  models)
    list_models
    ;;
  help|*)
    cat << 'HELP_EOF'
Google AI Provider

USAGE:
  google-provider <command> [arguments]

COMMANDS:
  complete <prompt> [model] [max_tokens] [temperature]
    Send a completion request to Google Generative AI API
    
  validate
    Validate the configured API key
    
  models
    List available Google models
    
  help
    Show this help message

ENVIRONMENT VARIABLES:
  GOOGLE_API_KEY    Required. Your Google API key

EXAMPLES:
  google-provider complete "Write a hello world function"
  google-provider complete "Analyze this code" gemini-1.5-pro 8192
  google-provider validate
  google-provider models
HELP_EOF
    ;;
esac
