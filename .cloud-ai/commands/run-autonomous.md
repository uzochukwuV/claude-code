---
description: "Run an autonomous AI task with Ralph loop"
argument-hint: "\"<prompt>\" [provider] [runtime] [max_iterations] [completion_promise]"
allowed-tools: ["Bash"]
---

# Run Autonomous Command

Execute an autonomous AI task using the Ralph Wiggum technique for iterative development.

```bash
#!/bin/bash
set -euo pipefail

CLOUD_AI_ROOT="${CLOUD_AI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CONFIG_FILE="${CLOUD_AI_ROOT}/config/provider-config.json"

PROMPT="${1:-}"
PROVIDER="${2:-}"
RUNTIME="${3:-}"
MAX_ITERATIONS="${4:-0}"
COMPLETION_PROMISE="${5:-}"

if [[ -z "$PROMPT" ]]; then
  echo "❌ Prompt required"
  echo ""
  echo "Usage: /run-autonomous \"<prompt>\" [provider] [runtime] [max_iterations] [completion_promise]"
  echo ""
  echo "Arguments:"
  echo "  prompt             - Task description (required, use quotes)"
  echo "  provider           - AI provider: anthropic, openai, google, custom (default: from config)"
  echo "  runtime            - Runtime: docker, github-codespaces, tripod (default: from config)"
  echo "  max_iterations     - Max loop iterations, 0=unlimited (default: 0)"
  echo "  completion_promise - Phrase to detect completion (optional)"
  echo ""
  echo "Examples:"
  echo "  /run-autonomous \"Build a REST API for todos\""
  echo "  /run-autonomous \"Fix the auth bug\" openai docker 50 \"Bug fixed\""
  echo "  /run-autonomous \"Deploy to production\" anthropic github-codespaces 0 \"DONE\""
  exit 1
fi

# Get defaults from config if not specified
if [[ -z "$PROVIDER" ]]; then
  PROVIDER=$(jq -r '.default_provider // "anthropic"' "$CONFIG_FILE")
fi

if [[ -z "$RUNTIME" ]]; then
  RUNTIME=$(jq -r '.runtime.default // "docker"' "$CONFIG_FILE")
fi

echo "🚀 Starting autonomous Cloud AI task"
echo "===================================="
echo ""
echo "  Prompt: $PROMPT"
echo "  Provider: $PROVIDER"
echo "  Runtime: $RUNTIME"
echo "  Max iterations: $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo $MAX_ITERATIONS; else echo "unlimited"; fi)"
if [[ -n "$COMPLETION_PROMISE" ]]; then
  echo "  Completion promise: $COMPLETION_PROMISE"
fi
echo ""

# Validate provider has API key set
ENV_VAR=$(jq -r ".providers.${PROVIDER}.env_var // empty" "$CONFIG_FILE")
if [[ -n "$ENV_VAR" ]] && [[ -z "${!ENV_VAR:-}" ]]; then
  echo "❌ Provider API key not set"
  echo "   Set environment variable: $ENV_VAR"
  echo ""
  echo "Or configure the provider:"
  echo "  /configure-provider $PROVIDER <your-api-key>"
  exit 1
fi

# Export provider-specific variables
export CURRENT_AI_PROVIDER="$PROVIDER"
echo "✅ Using $PROVIDER (from $ENV_VAR)"

# Execute in runtime
RUNTIME_SCRIPT="${CLOUD_AI_ROOT}/runtimes/${RUNTIME}.sh"

if [[ ! -f "$RUNTIME_SCRIPT" ]]; then
  echo "❌ Runtime script not found: $RUNTIME_SCRIPT"
  echo "Available runtimes:"
  ls -1 "${CLOUD_AI_ROOT}/runtimes/"*.sh 2>/dev/null | xargs -I {} basename {} .sh | sed 's/^/  - /' || echo "  None found"
  exit 1
fi

chmod +x "$RUNTIME_SCRIPT"

echo ""
echo "🔄 Launching Ralph loop in $RUNTIME..."
echo ""

# Run based on runtime type
case "$RUNTIME" in
  docker)
    "${RUNTIME_SCRIPT}" run-autonomous cloud-ai-runtime "$PROMPT" "$MAX_ITERATIONS" "$COMPLETION_PROMISE"
    ;;
  github-codespaces|codespace|codespaces)
    "${RUNTIME_SCRIPT}" run-autonomous "" "$PROMPT" "$MAX_ITERATIONS" "$COMPLETION_PROMISE"
    ;;
  tripod)
    "${RUNTIME_SCRIPT}" run-autonomous cloud-ai-env "$PROMPT" "$MAX_ITERATIONS" "$COMPLETION_PROMISE"
    ;;
  kubernetes|k8s)
    "${RUNTIME_SCRIPT}" run-autonomous cloud-ai-pod "$PROMPT" "$MAX_ITERATIONS" "$COMPLETION_PROMISE"
    ;;
  *)
    echo "❌ Unsupported runtime: $RUNTIME"
    exit 1
    ;;
esac
```

Usage examples:
- `/run-autonomous "Build a REST API for todos"` - Run with defaults
- `/run-autonomous "Fix the auth bug" openai docker 50 "Bug fixed"` - Specific provider/runtime
- `/run-autonomous "Deploy to production" anthropic github-codespaces` - Deploy to Codespaces
- `/run-autonomous "Refactor cache layer" custom 0 "TASK COMPLETE"` - Custom provider, unlimited

To signal completion, the AI must output: `<promise>YOUR_PHRASE</promise>`
