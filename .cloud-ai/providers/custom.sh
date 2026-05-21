#!/bin/bash

# Custom AI Provider Implementation
# Handles API communication with custom/compatible AI endpoints
# Supports any OpenAI-compatible API (LocalAI, Ollama, vLLM, etc.)

set -euo pipefail

# Load configuration
PROVIDER_CONFIG="${CLOUD_AI_ROOT}/config/provider-config.json"

# Get API endpoint from configuration or environment
get_api_endpoint() {
  local endpoint="${CUSTOM_AI_API_ENDPOINT:-}"
  if [[ -z "$endpoint" ]]; then
    endpoint=$(jq -r '.providers.custom.api_endpoint // empty' "$PROVIDER_CONFIG")
  fi
  if [[ -z "$endpoint" ]]; then
    echo "❌ Error: CUSTOM_AI_API_ENDPOINT environment variable not set and no endpoint in config" >&2
    exit 1
  fi
  echo "$endpoint"
}

# Get API key from environment
get_api_key() {
  local api_key="${CUSTOM_AI_API_KEY:-}"
  if [[ -z "$api_key" ]]; then
    api_key=$(jq -r '.providers.custom.env_var // "CUSTOM_AI_API_KEY"' "$PROVIDER_CONFIG")
    api_key="${!api_key:-}"
  fi
  echo "$api_key"
}

# Get auth header configuration
get_auth_header() {
  local header
  header=$(jq -r '.providers.custom.auth_header // "Authorization"' "$PROVIDER_CONFIG")
  echo "$header"
}

# Get auth prefix configuration
get_auth_prefix() {
  local prefix
  prefix=$(jq -r '.providers.custom.auth_prefix // "Bearer"' "$PROVIDER_CONFIG")
  echo "$prefix"
}

# Get model from configuration or argument
get_model() {
  local model="${1:-}"
  if [[ -z "$model" ]]; then
    model=$(jq -r '.providers.custom.models.default // empty' "$PROVIDER_CONFIG")
  fi
  if [[ -z "$model" ]]; then
    echo "❌ Error: No model specified and no default model in config" >&2
    exit 1
  fi
  echo "$model"
}

# Send completion request to custom API
# Usage: custom_complete "prompt" [model] [max_tokens] [temperature]
custom_complete() {
  local prompt="$1"
  local model="${2:-$(get_model)}"
  local max_tokens="${3:-4096}"
  local temperature="${4:-0.7}"
  
  local endpoint
  endpoint=$(get_api_endpoint)
  local api_key
  api_key=$(get_api_key)
  local auth_header
  auth_header=$(get_auth_header)
  local auth_prefix
  auth_prefix=$(get_auth_prefix)
  
  local auth_value
  if [[ -n "$api_key" ]] && [[ "$auth_prefix" != "null" ]]; then
    auth_value="$auth_prefix $api_key"
  else
    auth_value="$api_key"
  fi
  
  local response
  response=$(curl -s -X POST "${endpoint}/chat/completions" \
    -H "Content-Type: application/json" \
    -H "$auth_header: $auth_value" \
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

# Stream completion request
custom_stream() {
  local prompt="$1"
  local model="${2:-$(get_model)}"
  
  local endpoint
  endpoint=$(get_api_endpoint)
  local api_key
  api_key=$(get_api_key)
  local auth_header
  auth_header=$(get_auth_header)
  local auth_prefix
  auth_prefix=$(get_auth_prefix)
  
  local auth_value
  if [[ -n "$api_key" ]] && [[ "$auth_prefix" != "null" ]]; then
    auth_value="$auth_prefix $api_key"
  else
    auth_value="$api_key"
  fi
  
  curl -s -X POST "${endpoint}/chat/completions" \
    -H "Content-Type: application/json" \
    -H "$auth_header: $auth_value" \
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

# Validate API endpoint and key
validate_connection() {
  local endpoint
  endpoint=$(get_api_endpoint)
  local api_key
  api_key=$(get_api_key)
  local auth_header
  auth_header=$(get_auth_header)
  local auth_prefix
  auth_prefix=$(get_auth_prefix)
  
  local auth_value
  if [[ -n "$api_key" ]] && [[ "$auth_prefix" != "null" ]]; then
    auth_value="$auth_prefix $api_key"
  else
    auth_value="$api_key"
  fi
  
  # Try to hit the models endpoint or root
  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" \
    -X GET "${endpoint}/models" \
    -H "$auth_header: $auth_value" 2>/dev/null || echo "000")
  
  if [[ "$response" == "200" ]] || [[ "$response" == "404" ]]; then
    # 404 is okay - endpoint exists but no /models route
    echo "✅ Custom AI endpoint is reachable at $endpoint"
    return 0
  else
    echo "❌ Custom AI endpoint connection failed (HTTP $response)"
    return 1
  fi
}

# List available models (if supported)
list_models() {
  local endpoint
  endpoint=$(get_api_endpoint)
  local api_key
  api_key=$(get_api_key)
  local auth_header
  auth_header=$(get_auth_header)
  local auth_prefix
  auth_prefix=$(get_auth_prefix)
  
  local auth_value
  if [[ -n "$api_key" ]] && [[ "$auth_prefix" != "null" ]]; then
    auth_value="$auth_prefix $api_key"
  else
    auth_value="$api_key"
  fi
  
  curl -s "${endpoint}/models" \
    -H "$auth_header: $auth_value" 2>/dev/null | jq -r '.data[]? | {id, object, owned_by}' || echo "Model listing not supported by this endpoint"
}

# Main command handler
case "${1:-help}" in
  complete)
    shift
    custom_complete "$@"
    ;;
  stream)
    shift
    custom_stream "$@"
    ;;
  validate)
    validate_connection
    ;;
  models)
    list_models
    ;;
  help|*)
    cat << 'HELP_EOF'
Custom AI Provider

USAGE:
  custom-provider <command> [arguments]

COMMANDS:
  complete <prompt> [model] [max_tokens] [temperature]
    Send a completion request to custom AI API
    
  stream <prompt> [model]
    Stream a completion request (useful for long responses)
    
  validate
    Validate the configured API endpoint and key
    
  models
    List available models (if supported by endpoint)
    
  help
    Show this help message

ENVIRONMENT VARIABLES:
  CUSTOM_AI_API_ENDPOINT    Required. Base URL of your custom AI API
  CUSTOM_AI_API_KEY         Optional. API key for authentication

CONFIGURATION:
  Edit .cloud-ai/config/provider-config.json to customize:
  - api_endpoint: Base URL of your AI API
  - auth_header: Header name for auth (default: Authorization)
  - auth_prefix: Auth token prefix (default: Bearer)
  - models.default: Default model to use

SUPPORTED ENDPOINTS:
  - OpenAI-compatible APIs (LocalAI, Ollama, vLLM, etc.)
  - Any REST API following OpenAI chat completions format

EXAMPLES:
  # Using environment variables
  export CUSTOM_AI_API_ENDPOINT="http://localhost:11434/v1"
  custom-provider complete "Hello" llama3.1
  
  # Using Ollama
  export CUSTOM_AI_API_ENDPOINT="http://localhost:11434/v1"
  custom-provider complete "Write code" codellama
  
  # Using LocalAI
  export CUSTOM_AI_API_ENDPOINT="http://localhost:8080/v1"
  custom-provider complete "Analyze this" gpt-3.5-turbo
HELP_EOF
    ;;
esac
