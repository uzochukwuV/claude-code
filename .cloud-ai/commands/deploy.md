---
description: "Deploy Cloud AI to a runtime environment"
argument-hint: "[runtime] [options]"
allowed-tools: ["Bash"]
---

# Deploy Command

Deploy Cloud AI to the specified runtime environment.

```bash
#!/bin/bash
set -euo pipefail

CLOUD_AI_ROOT="${CLOUD_AI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RUNTIME="${1:-docker}"

case "$RUNTIME" in
  docker)
    echo "🚀 Deploying to Docker..."
    "${CLOUD_AI_ROOT}/runtimes/docker.sh" build
    "${CLOUD_AI_ROOT}/runtimes/docker.sh" start cloud-ai-runtime
    ;;
  github-codespaces|codespace|codespaces)
    echo "🚀 Deploying to GitHub Codespaces..."
    "${CLOUD_AI_ROOT}/runtimes/github-codespaces.sh" create "" main
    ;;
  tripod)
    echo "🚀 Deploying to Tripod..."
    "${CLOUD_AI_ROOT}/runtimes/tripod.sh" create cloud-ai-env us-east-1 medium
    ;;
  kubernetes|k8s)
    echo "🚀 Deploying to Kubernetes..."
    "${CLOUD_AI_ROOT}/runtimes/kubernetes.sh" deploy
    ;;
  *)
    echo "❌ Unknown runtime: $RUNTIME"
    echo "Available runtimes: docker, github-codespaces, tripod, kubernetes"
    exit 1
    ;;
esac

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "  /run-autonomous \"Your task description\""
```

Usage examples:
- `/deploy docker` - Deploy to local Docker
- `/deploy github-codespaces` - Deploy to GitHub Codespaces  
- `/deploy tripod` - Deploy to Tripod cloud
- `/deploy kubernetes` - Deploy to Kubernetes cluster
