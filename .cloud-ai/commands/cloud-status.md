---
description: "Show Cloud AI status across providers and runtimes"
argument-hint: ""
allowed-tools: ["Bash"]
---

# Cloud Status Command

Display the current status of Cloud AI configuration, providers, and runtimes.

```bash
#!/bin/bash
set -euo pipefail

CLOUD_AI_ROOT="${CLOUD_AI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CONFIG_FILE="${CLOUD_AI_ROOT}/config/provider-config.json"

echo "📊 Cloud AI Status"
echo "=================="
echo ""

# Configuration file
echo "Configuration:"
echo "  Config file: $CONFIG_FILE"
if [[ -f "$CONFIG_FILE" ]]; then
  echo "  ✅ Config exists"
else
  echo "  ❌ Config not found"
fi
echo ""

# Current defaults
echo "Defaults:"
DEFAULT_PROVIDER=$(jq -r '.default_provider // "anthropic"' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
DEFAULT_RUNTIME=$(jq -r '.runtime.default // "docker"' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
echo "  Default provider: $DEFAULT_PROVIDER"
echo "  Default runtime: $DEFAULT_RUNTIME"
echo ""

# Provider status
echo "Providers:"
echo "----------"
for provider in $(jq -r '.providers | keys[]' "$CONFIG_FILE" 2>/dev/null); do
  enabled=$(jq -r ".providers.${provider}.enabled" "$CONFIG_FILE")
  env_var=$(jq -r ".providers.${provider}.env_var // \"N/A\"" "$CONFIG_FILE")
  default_model=$(jq -r ".providers.${provider}.models.default // \"N/A\"" "$CONFIG_FILE")
  
  # Check if API key is set
  auth_status="❌ Not configured"
  if [[ -n "${!env_var:-}" ]]; then
    auth_status="✅ Configured"
  fi
  
  is_default=""
  if [[ "$provider" == "$DEFAULT_PROVIDER" ]]; then
    is_default=" (default)"
  fi
  
  echo "  $provider$is_default"
  echo "    Enabled: $enabled"
  echo "    Model: $default_model"
  echo "    Auth: $auth_status ($env_var)"
done
echo ""

# Runtime status
echo "Runtimes:"
echo "---------"
for runtime_file in "${CLOUD_AI_ROOT}/runtimes/"*.sh; do
  if [[ -f "$runtime_file" ]]; then
    runtime_name=$(basename "$runtime_file" .sh)
    is_default=""
    if [[ "$runtime_name" == "$DEFAULT_RUNTIME" ]]; then
      is_default=" (default)"
    fi
    
    # Check if runtime is available
    available="✅ Available"
    case "$runtime_name" in
      docker)
        if ! command -v docker &>/dev/null; then
          available="⚠️  Docker not installed"
        elif ! docker ps &>/dev/null; then
          available="⚠️  Docker daemon not running"
        fi
        ;;
      github-codespaces)
        if ! command -v gh &>/dev/null; then
          available="⚠️  GitHub CLI not installed"
        fi
        ;;
      tripod)
        if [[ -z "${TRIPOD_API_KEY:-}" ]]; then
          available="⚠️  TRIPOD_API_KEY not set"
        fi
        ;;
      kubernetes)
        if ! command -v kubectl &>/dev/null; then
          available="⚠️  kubectl not installed"
        fi
        ;;
    esac
    
    echo "  $runtime_name$is_default: $available"
  fi
done
echo ""

# Autonomy settings
echo "Autonomy Settings:"
MAX_ITERATIONS=$(jq -r '.autonomy.max_iterations // 0' "$CONFIG_FILE")
STATE_PERSISTENCE=$(jq -r '.autonomy.state_persistence // true' "$CONFIG_FILE")
echo "  Max iterations: $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo $MAX_ITERATIONS; else echo "unlimited"; fi)"
echo "  State persistence: $STATE_PERSISTENCE"
echo ""

# Quick actions
echo "Quick Actions:"
echo "  /configure-provider <provider> <api_key>  - Configure a provider"
echo "  /switch-runtime <runtime>                 - Switch runtime"
echo "  /run-autonomous \"<task>\"                  - Run autonomous task"
echo "  /deploy <runtime>                         - Deploy to runtime"
```

This command shows:
- Configuration file status
- Default provider and runtime
- All providers with their enabled status, models, and authentication state
- All runtimes with their availability status
- Autonomy settings
- Quick action commands
