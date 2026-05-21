#!/bin/bash

# GitHub Codespaces Runtime Adapter
# Manages Cloud AI execution in GitHub Codespaces environments

set -euo pipefail

# Configuration
CLOUD_AI_ROOT="${CLOUD_AI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${CLOUD_AI_ROOT}/config/provider-config.json"

# Default settings
DEFAULT_CODESPACE_NAME=""
GH_BINARY="gh"

# Check if gh CLI is available
check_gh_cli() {
  if ! command -v "$GH_BINARY" &>/dev/null; then
    echo "❌ Error: GitHub CLI (gh) is not installed"
    echo "   Install from: https://cli.github.com/"
    echo "   Or: brew install gh, apt-get install gh, etc."
    return 1
  fi
}

# Authenticate with GitHub
authenticate() {
  echo "🔐 Checking GitHub authentication..."
  
  if ! "$GH_BINARY" auth status &>/dev/null; then
    echo "⚠️  Not authenticated with GitHub"
    echo "   Run: gh auth login"
    echo ""
    read -p "Do you want to authenticate now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      "$GH_BINARY" auth login
    else
      echo "❌ Authentication required for Codespaces operations"
      return 1
    fi
  fi
  
  echo "✅ Authenticated as: $("$GH_BINARY" auth status 2>&1 | grep -oP 'Logged in account \K\S+')"
}

# List available codespaces
list_codespaces() {
  check_gh_cli || return 1
  
  echo "📦 GitHub Codespaces"
  echo "==================="
  echo ""
  
  "$GH_BINARY" codespace list --limit 20
}

# Get current codespace name (if running inside one)
get_current_codespace() {
  if [[ -n "${CODESPACES:-}" ]] && [[ "$CODESPACES" == "true" ]]; then
    echo "${CODESPACE_NAME:-}"
  else
    echo ""
  fi
}

# Create a new codespace
create_codespace() {
  check_gh_cli || return 1
  
  local repo="${1:-}"
  local branch="${2:-main}"
  local machine="${3:-}"
  local location="${4:-}"
  
  if [[ -z "$repo" ]]; then
    # Use current directory's git remote
    repo=$(git remote get-url origin 2>/dev/null | sed 's|.*:\(||.*\)|\1|' | sed 's|\.git$||')
    if [[ -z "$repo" ]]; then
      echo "❌ Error: No repository specified and no git remote found"
      echo "   Usage: codespace-runtime create <owner/repo> [branch] [machine]"
      return 1
    fi
  fi
  
  echo "🚀 Creating Codespace for $repo..."
  
  local create_args=""
  if [[ -n "$branch" ]] && [[ "$branch" != "main" ]]; then
    create_args="$create_args -b $branch"
  fi
  
  if [[ -n "$machine" ]]; then
    create_args="$create_args -m $machine"
  fi
  
  if [[ -n "$location" ]]; then
    create_args="$create_args -l $location"
  fi
  
  # Create codespace
  local codespace_name
  codespace_name=$("$GH_BINARY" codespace create $create_args -R "$repo" --display-name "cloud-ai" 2>&1)
  
  echo "✅ Codespace created: $codespace_name"
  echo ""
  echo "📋 To connect:"
  echo "   codespace-runtime connect $codespace_name"
  echo ""
  echo "📋 To run Cloud AI:"
  echo "   codespace-runtime exec $codespace_name 'claude'"
}

# Connect to a codespace via SSH
connect_codespace() {
  check_gh_cli || return 1
  
  local codespace_name="${1:-}"
  
  if [[ -z "$codespace_name" ]]; then
    # Try to find one with cloud-ai in the name
    codespace_name=$("$GH_BINARY" codespace list --limit 1 | awk 'NR>1 {print $1}')
    if [[ -z "$codespace_name" ]]; then
      echo "❌ No codespace specified and none found"
      echo "   Usage: codespace-runtime connect <codespace-name>"
      return 1
    fi
  fi
  
  echo "🔌 Connecting to Codespace: $codespace_name"
  echo "   This will open an SSH session. Exit to return."
  echo ""
  
  "$GH_BINARY" codespace ssh -c "$codespace_name"
}

# Execute command in codespace
exec_in_codespace() {
  check_gh_cli || return 1
  
  local codespace_name="${1:-}"
  shift
  local cmd="$*"
  
  if [[ -z "$codespace_name" ]]; then
    codespace_name=$(get_current_codespace)
    if [[ -z "$codespace_name" ]]; then
      echo "❌ No codespace specified and not running in a codespace"
      echo "   Usage: codespace-runtime exec <codespace-name> <command>"
      return 1
    fi
  fi
  
  "$GH_BINARY" codespace ssh -c "$codespace_name" -- bash -c "$cmd"
}

# Copy files to codespace
copy_to_codespace() {
  check_gh_cli || return 1
  
  local codespace_name="${1:-}"
  local source="${2:-}"
  local dest="${3:-/workspaces/}"
  
  if [[ -z "$codespace_name" ]] || [[ -z "$source" ]]; then
    echo "❌ Usage: codespace-runtime copy <codespace-name> <local-path> [remote-path]"
    return 1
  fi
  
  echo "📤 Copying $source to $codespace_name:$dest"
  
  "$GH_BINARY" codespace cp "$source" "$codespace_name:$dest"
}

# Copy files from codespace
copy_from_codespace() {
  check_gh_cli || return 1
  
  local codespace_name="${1:-}"
  local source="${2:-}"
  local dest="${3:-.}"
  
  if [[ -z "$codespace_name" ]] || [[ -z "$source" ]]; then
    echo "❌ Usage: codespace-runtime copy-from <codespace-name> <remote-path> [local-dest]"
    return 1
  fi
  
  echo "📥 Copying $codespace_name:$source to $dest"
  
  "$GH_BINARY" codespace cp "$codespace_name:$source" "$dest"
}

# Delete a codespace
delete_codespace() {
  check_gh_cli || return 1
  
  local codespace_name="${1:-}"
  
  if [[ -z "$codespace_name" ]]; then
    echo "❌ No codespace specified"
    echo "   Usage: codespace-runtime delete <codespace-name>"
    return 1
  fi
  
  echo "⚠️  Deleting codespace: $codespace_name"
  read -p "Are you sure? This cannot be undone. (y/n) " -n 1 -r
  echo
  
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    "$GH_BINARY" codespace delete -c "$codespace_name"
    echo "✅ Codespace deleted"
  else
    echo "❌ Deletion cancelled"
  fi
}

# Run Cloud AI autonomously in codespace
run_autonomous() {
  check_gh_cli || return 1
  
  local codespace_name="${1:-}"
  local prompt="${2:-}"
  local max_iterations="${3:-0}"
  local completion_promise="${4:-}"
  
  if [[ -z "$prompt" ]]; then
    echo "❌ Error: Prompt required for autonomous execution"
    echo "Usage: codespace-runtime run-autonomous <codespace> <prompt> [max_iterations] [completion_promise]"
    return 1
  fi
  
  if [[ -z "$codespace_name" ]]; then
    codespace_name=$(get_current_codespace)
    if [[ -z "$codespace_name" ]]; then
      echo "❌ No codespace specified"
      return 1
    fi
  fi
  
  echo "🔄 Starting autonomous execution in Codespace: $codespace_name"
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
  
  # Execute in codespace
  exec_in_codespace "$codespace_name" "cd /workspaces/\$(basename \$PWD) && $ralph_cmd"
}

# Get codespace status
status() {
  check_gh_cli || return 1
  
  local codespace_name="${1:-}"
  
  echo "📊 GitHub Codespaces Status"
  echo "=========================="
  echo ""
  
  if [[ -n "$codespace_name" ]]; then
    "$GH_BINARY" codespace list --limit 1 | grep "$codespace_name" || echo "Codespace not found: $codespace_name"
  else
    "$GH_BINARY" codespace list --limit 10
  fi
  
  # Check if running inside a codespace
  local current
  current=$(get_current_codespace)
  if [[ -n "$current" ]]; then
    echo ""
    echo "🟢 Currently running inside codespace: $current"
  fi
}

# Show help
show_help() {
  cat << 'HELP_EOF'
GitHub Codespaces Runtime Adapter

USAGE:
  codespace-runtime <command> [arguments]

COMMANDS:
  list
    List all your codespaces
    
  create [repo] [branch] [machine]
    Create a new codespace
    - repo: Owner/repo (default: current git remote)
    - branch: Git branch (default: main)
    - machine: Machine type (e.g., standardLinux, premiumLinux)
    
  connect [codespace-name]
    Connect to a codespace via SSH
    
  exec <codespace-name> <command>
    Execute a command in a codespace
    
  copy <codespace-name> <local-path> [remote-path]
    Copy files to a codespace
    
  copy-from <codespace-name> <remote-path> [local-dest]
    Copy files from a codespace
    
  delete <codespace-name>
    Delete a codespace
    
  run-autonomous <codespace> <prompt> [max_iterations] [completion_promise]
    Run Cloud AI autonomously using Ralph loop
    
  status [codespace-name]
    Show codespace status
    
  auth
    Check/authentication with GitHub
    
  help
    Show this help message

ENVIRONMENT VARIABLES:
  CODESPACES         Set to "true" when running inside a codespace
  CODESPACE_NAME     Name of the current codespace (when inside one)
  GITHUB_TOKEN       GitHub personal access token (optional)

EXAMPLES:
  # List codespaces
  codespace-runtime list
  
  # Create new codespace
  codespace-runtime create owner/repo main standardLinux
  
  # Execute commands
  codespace-runtime exec my-codespace "cd /workspaces/myapp && npm install"
  
  # Run autonomous task
  codespace-runtime run-autonomous my-codespace "Build API" 50 "DONE"
  
  # Copy files
  codespace-runtime copy my-codespace ./src /workspaces/myapp/
  codespace-runtime copy-from my-codespace /workspaces/myapp/dist ./output

NOTES:
  - Requires GitHub CLI (gh) to be installed
  - Must be authenticated: gh auth login
  - When running inside a codespace, commands target the current codespace
  - Codespaces bill based on compute time - delete when not in use

GITHUB CODESPACES API:
  - REST API: https://api.github.com/user/codespaces
  - Docs: https://docs.github.com/en/codespaces
HELP_EOF
}

# Main command handler
case "${1:-help}" in
  list)
    list_codespaces
    ;;
  create)
    shift
    create_codespace "$@"
    ;;
  connect)
    shift
    connect_codespace "$@"
    ;;
  exec)
    shift
    exec_in_codespace "$@"
    ;;
  copy)
    shift
    copy_to_codespace "$@"
    ;;
  copy-from)
    shift
    copy_from_codespace "$@"
    ;;
  delete)
    shift
    delete_codespace "$@"
    ;;
  run-autonomous)
    shift
    run_autonomous "$@"
    ;;
  status)
    shift
    status "$@"
    ;;
  auth)
    authenticate
    ;;
  help|*)
    show_help
    ;;
esac
