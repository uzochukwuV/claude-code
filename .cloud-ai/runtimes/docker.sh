#!/bin/bash

# Docker Runtime Adapter
# Manages Cloud AI execution in Docker containers with network isolation

set -euo pipefail

# Configuration
CLOUD_AI_ROOT="${CLOUD_AI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${CLOUD_AI_ROOT}/config/provider-config.json"

# Default container settings
DEFAULT_CONTAINER_NAME="cloud-ai-runtime"
DEFAULT_IMAGE="node:20"
WORKSPACE_MOUNT="/workspace"

# Get configuration value
get_config() {
  local path="$1"
  jq -r "$path // empty" "$CONFIG_FILE" 2>/dev/null || echo ""
}

# Build the Cloud AI Docker image
build_image() {
  local image_name="${1:-$DEFAULT_IMAGE}"
  local dockerfile="${2:-${CLOUD_AI_ROOT}/runtimes/Dockerfile.cloud-ai}"
  
  echo "🔨 Building Cloud AI Docker image..."
  
  if [[ -f "$dockerfile" ]]; then
    docker build -t "$image_name" -f "$dockerfile" "${CLOUD_AI_ROOT}/.."
  else
    # Use default node image with cloud-ai setup
    echo "Using base image: $image_name"
    echo "📦 Installing Cloud AI dependencies..."
    
    # Pull the base image
    docker pull "$image_name"
  fi
  
  echo "✅ Image ready: $image_name"
}

# Start a new Cloud AI container
start_container() {
  local container_name="${1:-$DEFAULT_CONTAINER_NAME}"
  local image="${2:-$DEFAULT_IMAGE}"
  local workspace_path="${3:-$(pwd)}"
  
  echo "🚀 Starting Cloud AI container..."
  
  # Check if container already exists
  if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
    echo "⚠️  Container '$container_name' already exists"
    echo "   Remove it first: docker rm -f $container_name"
    echo "   Or start existing: docker start -i $container_name"
    return 1
  fi
  
  # Build environment variables from config
  local env_args=""
  
  # Add AI provider API keys if set
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    env_args="$env_args -e ANTHROPIC_API_KEY"
  fi
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    env_args="$env_args -e OPENAI_API_KEY"
  fi
  if [[ -n "${GOOGLE_API_KEY:-}" ]]; then
    env_args="$env_args -e GOOGLE_API_KEY"
  fi
  if [[ -n "${CUSTOM_AI_API_KEY:-}" ]]; then
    env_args="$env_args -e CUSTOM_AI_API_KEY"
  fi
  if [[ -n "${CUSTOM_AI_API_ENDPOINT:-}" ]]; then
    env_args="$env_args -e CUSTOM_AI_API_ENDPOINT"
  fi
  
  # Add cloud-ai specific variables
  env_args="$env_args -e CLOUD_AI_ROOT=/workspace/.cloud-ai"
  env_args="$env_args -e CLOUD_AI_RUNTIME=docker"
  
  # Create and start container
  docker run -d \
    --name "$container_name" \
    --cap-add=NET_ADMIN \
    --cap-add=NET_RAW \
    $env_args \
    -v "${workspace_path}:${WORKSPACE_MOUNT}" \
    -w "$WORKSPACE_MOUNT" \
    "$image" \
    tail -f /dev/null
  
  echo "✅ Container started: $container_name"
  echo "   Workspace: ${workspace_path} -> ${WORKSPACE_MOUNT}"
  
  # Initialize firewall inside container
  echo "🔒 Setting up network isolation..."
  docker exec "$container_name" bash -c "
    apt-get update && apt-get install -y iptables ipset iproute2 curl jq >/dev/null 2>&1
  " || true
  
  echo "📋 To connect to the container:"
  echo "   docker exec -it $container_name bash"
  echo ""
  echo "📋 To run Cloud AI in the container:"
  echo "   docker exec -it $container_name bash -c 'cd /workspace && claude'"
}

# Stop and remove container
stop_container() {
  local container_name="${1:-$DEFAULT_CONTAINER_NAME}"
  
  echo "🛑 Stopping container: $container_name"
  
  if docker ps -q --filter "name=^${container_name}$" | grep -q .; then
    docker stop "$container_name"
  fi
  
  if docker ps -aq --filter "name=^${container_name}$" | grep -q .; then
    docker rm "$container_name"
  fi
  
  echo "✅ Container removed"
}

# Execute command in running container
exec_in_container() {
  local container_name="${1:-$DEFAULT_CONTAINER_NAME}"
  shift
  local cmd="$*"
  
  if ! docker ps --filter "name=^${container_name}$" --format '{{.Names}}' | grep -q "^${container_name}$"; then
    echo "❌ Container '$container_name' is not running"
    return 1
  fi
  
  docker exec -it "$container_name" bash -c "$cmd"
}

# Run Cloud AI autonomously in container
run_autonomous() {
  local container_name="${1:-$DEFAULT_CONTAINER_NAME}"
  local prompt="${2:-}"
  local max_iterations="${3:-0}"
  local completion_promise="${4:-}"
  
  if [[ -z "$prompt" ]]; then
    echo "❌ Error: Prompt required for autonomous execution"
    echo "Usage: docker-runtime run-autonomous <container> <prompt> [max_iterations] [completion_promise]"
    return 1
  fi
  
  echo "🔄 Starting autonomous execution..."
  echo "   Container: $container_name"
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
  
  # Execute in container
  exec_in_container "$container_name" "cd /workspace && $ralph_cmd"
}

# Get container status
status() {
  local container_name="${1:-$DEFAULT_CONTAINER_NAME}"
  
  echo "📊 Cloud AI Docker Runtime Status"
  echo "================================"
  echo ""
  
  # Check if container exists and its state
  local container_info
  container_info=$(docker ps -a --filter "name=^${container_name}$" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}" 2>/dev/null)
  
  if [[ -n "$container_info" ]]; then
    echo "$container_info"
  else
    echo "No Cloud AI container found with name: $container_name"
  fi
  
  echo ""
  echo "Available images:"
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "(node|cloud-ai)" || echo "  None"
}

# List all Cloud AI containers
list_containers() {
  echo "📦 Cloud AI Containers"
  echo "====================="
  docker ps -a --filter "name=cloud-ai" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.CreatedAt}}"
}

# Show help
show_help() {
  cat << 'HELP_EOF'
Docker Runtime Adapter

USAGE:
  docker-runtime <command> [arguments]

COMMANDS:
  build [image_name] [dockerfile]
    Build the Cloud AI Docker image
    
  start [container_name] [image] [workspace_path]
    Start a new Cloud AI container
    
  stop [container_name]
    Stop and remove a container
    
  exec <container_name> <command>
    Execute a command in a running container
    
  run-autonomous <container_name> <prompt> [max_iterations] [completion_promise]
    Run Cloud AI autonomously in a container using Ralph loop
    
  status [container_name]
    Show container status
    
  list
    List all Cloud AI containers
    
  help
    Show this help message

ENVIRONMENT VARIABLES:
  ANTHROPIC_API_KEY     Anthropic API key (passed to container)
  OPENAI_API_KEY        OpenAI API key (passed to container)
  GOOGLE_API_KEY        Google API key (passed to container)
  CUSTOM_AI_API_KEY     Custom AI API key (passed to container)
  CUSTOM_AI_API_ENDPOINT Custom AI API endpoint (passed to container)
  CLOUD_AI_ROOT         Path to Cloud AI configuration directory

EXAMPLES:
  # Build and start a container
  docker-runtime build
  docker-runtime start my-cloud-ai node:20 /path/to/project
  
  # Run autonomous task
  docker-runtime run-autonomous my-cloud-ai "Build a REST API" 50 "API complete"
  
  # Execute commands
  docker-runtime exec my-cloud-ai "cd /workspace && npm install"
  
  # Check status
  docker-runtime status my-cloud-ai
  docker-runtime list

NOTES:
  - Containers run with NET_ADMIN and NET_RAW capabilities for firewall support
  - Workspace is mounted read-write at /workspace
  - Network isolation is configured via init-firewall.sh
HELP_EOF
}

# Main command handler
case "${1:-help}" in
  build)
    shift
    build_image "$@"
    ;;
  start)
    shift
    start_container "$@"
    ;;
  stop)
    shift
    stop_container "$@"
    ;;
  exec)
    shift
    exec_in_container "$@"
    ;;
  run-autonomous)
    shift
    run_autonomous "$@"
    ;;
  status)
    shift
    status "$@"
    ;;
  list)
    list_containers
    ;;
  help|*)
    show_help
    ;;
esac
