---
description: "Switch to a different runtime environment"
argument-hint: "<runtime>"
allowed-tools: ["Bash"]
---

# Switch Runtime Command

Switch the default runtime environment for Cloud AI operations.

```bash
#!/bin/bash
set -euo pipefail

CLOUD_AI_ROOT="${CLOUD_AI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CONFIG_FILE="${CLOUD_AI_ROOT}/config/provider-config.json"

RUNTIME="${1:-}"

if [[ -z "$RUNTIME" ]]; then
  echo "❌ Runtime name required"
  echo ""
  echo "Usage: /switch-runtime <runtime>"
  echo ""
  echo "Available runtimes:"
  echo "  docker            - Local Docker containers (default)"
  echo "  github-codespaces - GitHub Codespaces environments"
  echo "  tripod            - Tripod cloud environments"
  echo "  kubernetes        - Kubernetes clusters"
  echo ""
  echo "Current runtime: $(jq -r '.runtime.default // "docker"' "$CONFIG_FILE")"
  echo ""
  echo "Examples:"
  echo "  /switch-runtime docker"
  echo "  /switch-runtime github-codespaces"
  echo "  /switch-runtime tripod"
  exit 1
fi

# Validate runtime script exists
RUNTIME_SCRIPT="${CLOUD_AI_ROOT}/runtimes/${RUNTIME}.sh"
if [[ ! -f "$RUNTIME_SCRIPT" ]]; then
  echo "❌ Runtime not found: $RUNTIME"
  echo "   Script not found: $RUNTIME_SCRIPT"
  echo ""
  echo "Available runtimes:"
  ls -1 "${CLOUD_AI_ROOT}/runtimes/"*.sh 2>/dev/null | xargs -I {} basename {} .sh | sed 's/^/  - /' || echo "  None found"
  exit 1
fi

# Update config
TEMP_FILE="${CONFIG_FILE}.tmp"
jq ".runtime.default = \"$RUNTIME\"" "$CONFIG_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$CONFIG_FILE"

echo "✅ Switched to runtime: $RUNTIME"
echo ""
echo "Runtime details:"
chmod +x "$RUNTIME_SCRIPT"
"${RUNTIME_SCRIPT}" help 2>/dev/null | head -20 || true
```

Usage examples:
- `/switch-runtime docker` - Use local Docker containers
- `/switch-runtime github-codespaces` - Use GitHub Codespaces
- `/switch-runtime tripod` - Use Tripod cloud environments
- `/switch-runtime kubernetes` - Use Kubernetes clusters
