#!/bin/bash

# Cloud AI Orchestrator
# Main entry point for autonomous Cloud AI operations
# Manages provider selection, runtime execution, and autonomous loops

set -euo pipefail

# Configuration
export CLOUD_AI_ROOT="${CLOUD_AI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
CONFIG_FILE="${CLOUD_AI_ROOT}/config/provider-config.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get current provider configuration
get_current_provider() {
  jq -r '.providers.default // "anthropic"' "$CONFIG_FILE"
}

# Get enabled providers
get_enabled_providers() {
  jq -r '.providers | to_entries[] | select(.value.enabled == true) | .key' "$CONFIG_FILE"
}

# Check if provider API key is set
check_provider_auth() {
  local provider="$1"
  local env_var
  
  env_var=$(jq -r ".providers.${provider}.env_var // empty" "$CONFIG_FILE")
  
  if [[ -n "$env_var" ]] && [[ -n "${!env_var:-}" ]]; then
    return 0
  else
    return 1
  fi
}

# Validate provider configuration
validate_provider() {
  local provider="$1"
  
  log_info "Validating $provider provider..."
  
  case "$provider" in
    anthropic)
      "${CLOUD_AI_ROOT}/providers/anthropic.sh" validate
      ;;
    openai)
      "${CLOUD_AI_ROOT}/providers/openai.sh" validate
      ;;
    google)
      "${CLOUD_AI_ROOT}/providers/google.sh" validate
      ;;
    custom)
      "${CLOUD_AI_ROOT}/providers/custom.sh" validate
      ;;
    *)
      log_error "Unknown provider: $provider"
      return 1
      ;;
  esac
}

# Switch to a different provider
switch_provider() {
  local provider="$1"
  
  if ! jq -e ".providers.${provider}" "$CONFIG_FILE" >/dev/null; then
    log_error "Unknown provider: $provider"
    echo "Available providers: $(jq -r '.providers | keys | join(", ")' "$CONFIG_FILE")"
    return 1
  fi
  
  # Update default in config
  local temp_file="${CONFIG_FILE}.tmp"
  jq ".default = \"$provider\"" "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
  
  log_success "Switched to provider: $provider"
  
  # Check authentication
  if ! check_provider_auth "$provider"; then
    local env_var
    env_var=$(jq -r ".providers.${provider}.env_var" "$CONFIG_FILE")
    log_warning "API key not set. Set $env_var environment variable."
  fi
}

# Get current runtime
get_current_runtime() {
  jq -r '.runtime.default // "docker"' "$CONFIG_FILE"
}

# List available runtimes
list_runtimes() {
  echo "📦 Available Runtimes:"
  echo "====================="
  for runtime_file in "${CLOUD_AI_ROOT}/runtimes/"*.sh; do
    local runtime_name
    runtime_name=$(basename "$runtime_file" .sh)
    echo "  - $runtime_name"
  done
}

# Initialize Cloud AI environment
init() {
  log_info "Initializing Cloud AI environment..."
  
  # Check for required tools
  local required_tools=("curl" "jq" "bash")
  for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      log_error "Required tool not found: $tool"
      return 1
    fi
  done
  
  # Validate config file
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    return 1
  fi
  
  if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    log_error "Invalid JSON in configuration file"
    return 1
  fi
  
  log_success "Cloud AI environment initialized"
  
  # Show current configuration
  echo ""
  echo "Current Configuration:"
  echo "  Provider: $(get_current_provider)"
  echo "  Runtime: $(get_current_runtime)"
  echo ""
  
  # Check provider auth
  local provider
  provider=$(get_current_provider)
  if check_provider_auth "$provider"; then
    echo "  ✅ $provider API key is set"
  else
    echo "  ⚠️  $provider API key not set"
  fi
}

# Run autonomous task with specified provider and runtime
run() {
  local prompt="${1:-}"
  local provider="${2:-}"
  local runtime="${3:-}"
  local max_iterations="${4:-0}"
  local completion_promise="${5:-}"
  
  if [[ -z "$prompt" ]]; then
    log_error "Prompt required"
    echo "Usage: cloud-ai run \"<prompt>\" [provider] [runtime] [max_iterations] [completion_promise]"
    return 1
  fi
  
  # Use defaults if not specified
  provider="${provider:-$(get_current_provider)}"
  runtime="${runtime:-$(get_current_runtime)}"
  
  log_info "Starting autonomous Cloud AI task"
  echo "  Prompt: $prompt"
  echo "  Provider: $provider"
  echo "  Runtime: $runtime"
  echo "  Max iterations: ${max_iterations:-unlimited}"
  echo "  Completion promise: ${completion_promise:-none}"
  echo ""
  
  # Validate provider
  if ! check_provider_auth "$provider"; then
    local env_var
    env_var=$(jq -r ".providers.${provider}.env_var" "$CONFIG_FILE")
    log_error "Provider API key not set. Set $env_var"
    return 1
  fi
  
  # Export provider-specific variables
  export_provider_env "$provider"
  
  # Execute in runtime
  local runtime_script="${CLOUD_AI_ROOT}/runtimes/${runtime}.sh"
  
  if [[ ! -f "$runtime_script" ]]; then
    log_error "Runtime script not found: $runtime_script"
    echo "Available runtimes:"
    list_runtimes
    return 1
  fi
  
  # Make executable
  chmod +x "$runtime_script"
  
  # Run based on runtime type
  case "$runtime" in
    docker)
      "${runtime_script}" run-autonomous cloud-ai-runtime "$prompt" "$max_iterations" "$completion_promise"
      ;;
    github-codespaces)
      "${runtime_script}" run-autonomous "" "$prompt" "$max_iterations" "$completion_promise"
      ;;
    tripod)
      "${runtime_script}" run-autonomous cloud-ai-env "$prompt" "$max_iterations" "$completion_promise"
      ;;
    *)
      log_error "Unsupported runtime: $runtime"
      return 1
      ;;
  esac
}

# Export provider-specific environment variables
export_provider_env() {
  local provider="$1"
  local env_var
  
  env_var=$(jq -r ".providers.${provider}.env_var // empty" "$CONFIG_FILE")
  
  if [[ -n "$env_var" ]] && [[ -n "${!env_var:-}" ]]; then
    export CURRENT_AI_PROVIDER="$provider"
    log_info "Using $provider (from $env_var)"
  fi
}

# Show status of Cloud AI environment
status() {
  echo "📊 Cloud AI Status"
  echo "================="
  echo ""
  
  # Configuration
  echo "Configuration:"
  echo "  Config file: $CONFIG_FILE"
  echo "  Default provider: $(get_current_provider)"
  echo "  Default runtime: $(get_current_runtime)"
  echo ""
  
  # Providers
  echo "Providers:"
  for provider in $(jq -r '.providers | keys[]' "$CONFIG_FILE"); do
    local enabled
    enabled=$(jq -r ".providers.${provider}.enabled" "$CONFIG_FILE")
    local auth_status="❌"
    if check_provider_auth "$provider"; then
      auth_status="✅"
    fi
    echo "  $provider: enabled=$enabled, auth=$auth_status"
  done
  echo ""
  
  # Runtime status
  echo "Runtime Status:"
  local current_runtime
  current_runtime=$(get_current_runtime)
  
  case "$current_runtime" in
    docker)
      "${CLOUD_AI_ROOT}/runtimes/docker.sh" status
      ;;
    github-codespaces)
      "${CLOUD_AI_ROOT}/runtimes/github-codespaces.sh" status
      ;;
    tripod)
      "${CLOUD_AI_ROOT}/runtimes/tripod.sh" status
      ;;
  esac
}

# Configure a provider
configure() {
  local provider="${1:-}"
  local key="${2:-}"
  local endpoint="${3:-}"
  
  if [[ -z "$provider" ]]; then
    log_error "Provider name required"
    echo "Usage: cloud-ai configure <provider> [api_key] [endpoint]"
    return 1
  fi
  
  if ! jq -e ".providers.${provider}" "$CONFIG_FILE" >/dev/null; then
    log_error "Unknown provider: $provider"
    return 1
  fi
  
  log_info "Configuring $provider provider..."
  
  local temp_file="${CONFIG_FILE}.tmp"
  local config_copy="$CONFIG_FILE"
  
  # Enable provider
  config_copy=$(echo "$config_copy" | jq ".providers.${provider}.enabled = true")
  
  # Set API key if provided
  if [[ -n "$key" ]]; then
    local env_var
    env_var=$(jq -r ".providers.${provider}.env_var" "$CONFIG_FILE")
    export "$env_var=$key"
    echo "  Set $env_var"
  fi
  
  # Set endpoint if provided (for custom provider)
  if [[ -n "$endpoint" ]]; then
    config_copy=$(echo "$config_copy" | jq ".providers.${provider}.api_endpoint = \"$endpoint\"")
  fi
  
  echo "$config_copy" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
  
  log_success "Provider configured: $provider"
}

# Show help
show_help() {
  cat << 'HELP_EOF'
Cloud AI Orchestrator

USAGE:
  cloud-ai <command> [arguments]

COMMANDS:
  init
    Initialize and validate Cloud AI environment
    
  run "<prompt>" [provider] [runtime] [max_iterations] [completion_promise]
    Run an autonomous AI task
    - prompt: Task description (required, use quotes)
    - provider: AI provider (default: from config)
    - runtime: Execution environment (default: from config)
    - max_iterations: Max loop iterations, 0=unlimited (default: 0)
    - completion_promise: Phrase to detect completion (optional)
    
  status
    Show current Cloud AI status
    
  switch-provider <provider>
    Switch to a different AI provider
    
  configure <provider> [api_key] [endpoint]
    Configure a provider
    
  list-providers
    List available AI providers
    
  list-runtimes
    List available runtimes
    
  validate-provider <provider>
    Validate provider configuration and API key
    
  help
    Show this help message

PROVIDERS:
  - anthropic: Anthropic Claude models (default)
  - openai: OpenAI GPT models
  - google: Google Gemini models
  - custom: Any OpenAI-compatible API

RUNTIMES:
  - docker: Local Docker containers (default)
  - github-codespaces: GitHub Codespaces
  - tripod: Tripod cloud environments

ENVIRONMENT VARIABLES:
  ANTHROPIC_API_KEY     Anthropic API key
  OPENAI_API_KEY        OpenAI API key
  GOOGLE_API_KEY        Google API key
  CUSTOM_AI_API_KEY     Custom AI API key
  CUSTOM_AI_API_ENDPOINT Custom AI API endpoint
  CLOUD_AI_ROOT         Path to Cloud AI installation

EXAMPLES:
  # Initialize
  cloud-ai init
  
  # Run autonomous task with defaults
  cloud-ai run "Build a REST API for todos"
  
  # Run with specific provider and runtime
  cloud-ai run "Fix the auth bug" openai docker 50 "Bug fixed"
  
  # Run in GitHub Codespaces
  cloud-ai run "Deploy to production" anthropic github-codespaces
  
  # Switch provider
  cloud-ai switch-provider openai
  
  # Configure custom provider
  cloud-ai configure custom my-key http://localhost:11434/v1
  
  # Check status
  cloud-ai status

AUTONOMOUS EXECUTION:
  Cloud AI uses the Ralph Wiggum technique for autonomous execution.
  The AI will iterate on the task until:
  - Max iterations reached, OR
  - Completion promise detected in output
  
  To signal completion, the AI must output:
  <promise>YOUR_COMPLETION_PHRASE</promise>

CONFIGURATION FILE:
  Location: .cloud-ai/config/provider-config.json
  
  Customize providers, models, and runtime settings there.
HELP_EOF
}

# List available providers
list_providers() {
  echo "📦 Available AI Providers"
  echo "========================"
  echo ""
  
  for provider in $(jq -r '.providers | keys[]' "$CONFIG_FILE"); do
    local enabled
    enabled=$(jq -r ".providers.${provider}.enabled" "$CONFIG_FILE")
    local default_model
    default_model=$(jq -r ".providers.${provider}.models.default // \"N/A\"" "$CONFIG_FILE")
    local is_default=""
    if [[ "$provider" == "$(get_current_provider)" ]]; then
      is_default=" (default)"
    fi
    
    echo "  $provider$is_default"
    echo "    Enabled: $enabled"
    echo "    Default model: $default_model"
    
    if check_provider_auth "$provider"; then
      echo "    Auth: ✅ Configured"
    else
      echo "    Auth: ❌ Not configured"
    fi
    echo ""
  done
}

# Main command handler
case "${1:-help}" in
  init)
    init
    ;;
  run)
    shift
    run "$@"
    ;;
  status)
    status
    ;;
  switch-provider)
    shift
    switch_provider "$@"
    ;;
  configure)
    shift
    configure "$@"
    ;;
  list-providers)
    list_providers
    ;;
  list-runtimes)
    list_runtimes
    ;;
  validate-provider)
    shift
    validate_provider "$@"
    ;;
  help|--help|-h|*)
    show_help
    ;;
esac
