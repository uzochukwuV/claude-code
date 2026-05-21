#!/bin/bash

# Tripod Runtime Adapter
# Manages Cloud AI execution in Tripod environments
# Note: Tripod is a hypothetical/placeholder runtime - adapt to your actual provider

set -euo pipefail

# Configuration
CLOUD_AI_ROOT="${CLOUD_AI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${CLOUD_AI_ROOT}/config/provider-config.json"

# Default settings
TRIPOD_BINARY="tripod"
TRIPOD_API_ENDPOINT="${TRIPOD_API_ENDPOINT:-https://api.tripod.dev}"
TRIPOD_API_KEY="${TRIPOD_API_KEY:-}"

# Check if tripod CLI is available
check_tripod_cli() {
  if ! command -v "$TRIPOD_BINARY" &>/dev/null; then
    echo "⚠️  Tripod CLI not found at '$TRIPOD_BINARY'"
    echo "   Install from: https://tripod.dev/docs/cli"
    echo "   Or set TRIPOD_BINARY to the correct path"
    return 1
  fi
}

# Authenticate with Tripod
authenticate() {
  echo "🔐 Checking Tripod authentication..."
  
  if [[ -z "$TRIPOD_API_KEY" ]]; then
    echo "⚠️  TRIPOD_API_KEY environment variable not set"
    echo "   Get your API key from: https://tripod.dev/dashboard"
    echo ""
    read -p "Enter your Tripod API key: " -s api_key
    echo
    export TRIPOD_API_KEY="$api_key"
  fi
  
  # Validate API key
  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" \
    -X GET "${TRIPOD_API_ENDPOINT}/v1/auth/verify" \
    -H "Authorization: Bearer $TRIPOD_API_KEY" 2>/dev/null || echo "000")
  
  if [[ "$response" == "200" ]]; then
    echo "✅ Authenticated with Tripod"
    return 0
  else
    echo "❌ Tripod authentication failed (HTTP $response)"
    return 1
  fi
}

# List available Tripod environments
list_environments() {
  if [[ -z "$TRIPOD_API_KEY" ]]; then
    echo "❌ TRIPOD_API_KEY not set"
    return 1
  fi
  
  echo "📦 Tripod Environments"
  echo "======================"
  echo ""
  
  curl -s "${TRIPOD_API_ENDPOINT}/v1/environments" \
    -H "Authorization: Bearer $TRIPOD_API_KEY" | jq -r '.environments[]? | "\(.name)\t\(.status)\t\(.region)\t\(.created_at)"'
}

# Create a new Tripod environment
create_environment() {
  if [[ -z "$TRIPOD_API_KEY" ]]; then
    echo "❌ TRIPOD_API_KEY not set"
    return 1
  fi
  
  local name="${1:-cloud-ai-env}"
  local region="${2:-us-east-1}"
  local size="${3:-medium}"
  
  echo "🚀 Creating Tripod environment: $name..."
  
  local response
  response=$(curl -s -X POST "${TRIPOD_API_ENDPOINT}/v1/environments" \
    -H "Authorization: Bearer $TRIPOD_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$name\",
      \"region\": \"$region\",
      \"size\": \"$size\",
      \"image\": \"node:20\"
    }")
  
  local env_id
  env_id=$(echo "$response" | jq -r '.environment.id // empty')
  
  if [[ -n "$env_id" ]]; then
    echo "✅ Environment created: $name (ID: $env_id)"
    echo ""
    echo "📋 To connect:"
    echo "   tripod-runtime connect $name"
  else
    echo "❌ Failed to create environment"
    echo "   Response: $response"
    return 1
  fi
}

# Connect to a Tripod environment
connect_environment() {
  local env_name="${1:-}"
  
  if [[ -z "$env_name" ]]; then
    echo "❌ No environment specified"
    echo "   Usage: tripod-runtime connect <environment-name>"
    return 1
  fi
  
  echo "🔌 Connecting to Tripod environment: $env_name"
  
  # Get SSH connection details
  local ssh_info
  ssh_info=$(curl -s "${TRIPOD_API_ENDPOINT}/v1/environments/${env_name}/ssh" \
    -H "Authorization: Bearer $TRIPOD_API_KEY" | jq -r '.ssh_command // empty')
  
  if [[ -n "$ssh_info" ]]; then
    eval "$ssh_info"
  else
    echo "❌ Could not get SSH connection info for: $env_name"
    return 1
  fi
}

# Execute command in Tripod environment
exec_in_environment() {
  local env_name="${1:-}"
  shift
  local cmd="$*"
  
  if [[ -z "$env_name" ]]; then
    echo "❌ No environment specified"
    echo "   Usage: tripod-runtime exec <environment-name> <command>"
    return 1
  fi
  
  # Get SSH connection details
  local ssh_host
  ssh_host=$(curl -s "${TRIPOD_API_ENDPOINT}/v1/environments/${env_name}/ssh" \
    -H "Authorization: Bearer $TRIPOD_API_KEY" | jq -r '.host // empty')
  
  if [[ -z "$ssh_host" ]]; then
    echo "❌ Could not get SSH host for: $env_name"
    return 1
  fi
  
  # Execute via SSH
  ssh -o StrictHostKeyChecking=no "${env_name}@${ssh_host}" "$cmd"
}

# Deploy Cloud AI to Tripod
deploy() {
  local env_name="${1:-cloud-ai-env}"
  local workspace_path="${2:-$(pwd)}"
  
  echo "🚀 Deploying Cloud AI to Tripod environment: $env_name"
  
  # Create tarball of workspace
  local tarball="/tmp/cloud-ai-deploy-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$tarball" -C "$(dirname "$workspace_path")" "$(basename "$workspace_path")"
  
  echo "📦 Created deployment package: $tarball"
  
  # Upload to Tripod
  local upload_url
  upload_url=$(curl -s -X POST "${TRIPOD_API_ENDPOINT}/v1/environments/${env_name}/upload" \
    -H "Authorization: Bearer $TRIPOD_API_KEY" | jq -r '.upload_url // empty')
  
  if [[ -z "$upload_url" ]]; then
    echo "❌ Could not get upload URL"
    rm "$tarball"
    return 1
  fi
  
  echo "📤 Uploading to Tripod..."
  curl -s -X PUT "$upload_url" -T "$tarball"
  
  rm "$tarball"
  
  echo "✅ Deployment complete"
  echo ""
  echo "📋 To run Cloud AI:"
  echo "   tripod-runtime exec $env_name 'cd /workspace && claude'"
}

# Run Cloud AI autonomously in Tripod
run_autonomous() {
  local env_name="${1:-}"
  local prompt="${2:-}"
  local max_iterations="${3:-0}"
  local completion_promise="${4:-}"
  
  if [[ -z "$prompt" ]]; then
    echo "❌ Error: Prompt required for autonomous execution"
    echo "Usage: tripod-runtime run-autonomous <env> <prompt> [max_iterations] [completion_promise]"
    return 1
  fi
  
  if [[ -z "$env_name" ]]; then
    echo "❌ No environment specified"
    return 1
  fi
  
  echo "🔄 Starting autonomous execution in Tripod: $env_name"
  echo "   Prompt: $prompt"
  echo "   Max iterations: ${max_iterations:-unlimited}"
  echo "   Completion promise: ${completion_promise:-none}"
  
  # Build ralph-loop command
  local ralph_cmd="/ralph-loop \"$prompt\""
  if [[ "$max_iterations" -gt 0 ]]; then
    ralph_cmd="$ralph_cmd --max-iterations $max_iterations"
  fi
  if [[ -n "$completion_promise" ]]; then
    ralph_cmd="$ralph_cmd --completion-promise '$completion_promise'"
  fi
  
  # Execute in environment
  exec_in_environment "$env_name" "cd /workspace && $ralph_cmd"
}

# Get environment status
status() {
  local env_name="${1:-}"
  
  echo "📊 Tripod Environment Status"
  echo "==========================="
  echo ""
  
  if [[ -z "$TRIPOD_API_KEY" ]]; then
    echo "❌ TRIPOD_API_KEY not set"
    return 1
  fi
  
  if [[ -n "$env_name" ]]; then
    curl -s "${TRIPOD_API_ENDPOINT}/v1/environments/${env_name}" \
      -H "Authorization: Bearer $TRIPOD_API_KEY" | jq '.'
  else
    curl -s "${TRIPOD_API_ENDPOINT}/v1/environments" \
      -H "Authorization: Bearer $TRIPOD_API_KEY" | jq '.environments[] | {name, status, region, created_at}'
  fi
}

# Delete a Tripod environment
delete_environment() {
  local env_name="${1:-}"
  
  if [[ -z "$env_name" ]]; then
    echo "❌ No environment specified"
    echo "   Usage: tripod-runtime delete <environment-name>"
    return 1
  fi
  
  echo "⚠️  Deleting Tripod environment: $env_name"
  read -p "Are you sure? This cannot be undone. (y/n) " -n 1 -r
  echo
  
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    curl -s -X DELETE "${TRIPOD_API_ENDPOINT}/v1/environments/${env_name}" \
      -H "Authorization: Bearer $TRIPOD_API_KEY"
    echo "✅ Environment deleted"
  else
    echo "❌ Deletion cancelled"
  fi
}

# Show help
show_help() {
  cat << 'HELP_EOF'
Tripod Runtime Adapter

USAGE:
  tripod-runtime <command> [arguments]

COMMANDS:
  list
    List all Tripod environments
    
  create [name] [region] [size]
    Create a new Tripod environment
    - name: Environment name (default: cloud-ai-env)
    - region: Cloud region (default: us-east-1)
    - size: Instance size (default: medium)
    
  connect <environment-name>
    Connect to a Tripod environment via SSH
    
  exec <environment-name> <command>
    Execute a command in a Tripod environment
    
  deploy [env-name] [workspace-path]
    Deploy current workspace to Tripod
    
  run-autonomous <env> <prompt> [max_iterations] [completion_promise]
    Run Cloud AI autonomously using Ralph loop
    
  status [environment-name]
    Show environment status
    
  delete <environment-name>
    Delete a Tripod environment
    
  auth
    Authenticate with Tripod
    
  help
    Show this help message

ENVIRONMENT VARIABLES:
  TRIPOD_API_KEY        Required. Your Tripod API key
  TRIPOD_API_ENDPOINT   Optional. Tripod API endpoint (default: https://api.tripod.dev)

EXAMPLES:
  # Create environment
  tripod-runtime create my-cloud-ai us-west-2 large
  
  # Deploy and run
  tripod-runtime deploy my-cloud-ai
  tripod-runtime exec my-cloud-ai "cd /workspace && npm install"
  
  # Run autonomous task
  tripod-runtime run-autonomous my-cloud-ai "Build REST API" 50 "DONE"

NOTES:
  - Tripod is a placeholder runtime - adapt to your actual provider
  - Replace API endpoints and commands with your provider's specifics
  - Pattern works for any cloud provider with SSH access

CUSTOMIZATION:
  To adapt for another provider:
  1. Update TRIPOD_API_ENDPOINT to your provider's API
  2. Modify authentication method
  3. Update create/connect/exec/delete functions
  4. Adjust deployment mechanism
HELP_EOF
}

# Main command handler
case "${1:-help}" in
  list)
    list_environments
    ;;
  create)
    shift
    create_environment "$@"
    ;;
  connect)
    shift
    connect_environment "$@"
    ;;
  exec)
    shift
    exec_in_environment "$@"
    ;;
  deploy)
    shift
    deploy "$@"
    ;;
  run-autonomous)
    shift
    run_autonomous "$@"
    ;;
  status)
    shift
    status "$@"
    ;;
  delete)
    shift
    delete_environment "$@"
    ;;
  auth)
    authenticate
    ;;
  help|*)
    show_help
    ;;
esac
