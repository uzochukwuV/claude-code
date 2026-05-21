#!/bin/bash

# Kubernetes Runtime Adapter
# Manages Cloud AI execution in Kubernetes clusters

set -euo pipefail

# Configuration
CLOUD_AI_ROOT="${CLOUD_AI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${CLOUD_AI_ROOT}/config/provider-config.json"

# Default settings
DEFAULT_NAMESPACE="${K8S_NAMESPACE:-cloud-ai}"
DEFAULT_CONTAINER_NAME="cloud-ai-runtime"
DEFAULT_IMAGE="node:20"
KUBECTL_BINARY="kubectl"

# Check if kubectl is available
check_kubectl() {
  if ! command -v "$KUBECTL_BINARY" &>/dev/null; then
    echo "❌ Error: kubectl is not installed"
    echo "   Install from: https://kubernetes.io/docs/tasks/tools/"
    return 1
  fi
  
  if ! "$KUBECTL_BINARY" cluster-info &>/dev/null; then
    echo "❌ Error: Cannot connect to Kubernetes cluster"
    echo "   Check your kubeconfig: kubectl config view"
    return 1
  fi
}

# Create namespace if not exists
ensure_namespace() {
  local namespace="${1:-$DEFAULT_NAMESPACE}"
  
  "$KUBECTL_BINARY" get namespace "$namespace" &>/dev/null || \
    "$KUBECTL_BINARY" create namespace "$namespace"
}

# Build and push Cloud AI image
build_image() {
  local image_name="${1:-cloud-ai-runtime}"
  local registry="${2:-}"
  local dockerfile="${3:-${CLOUD_AI_ROOT}/runtimes/Dockerfile.cloud-ai}"
  
  echo "🔨 Building Cloud AI Docker image..."
  
  if [[ -f "$dockerfile" ]]; then
    docker build -t "$image_name" -f "$dockerfile" "${CLOUD_AI_ROOT}/.."
  else
    echo "Using default node:20 image"
    image_name="node:20"
  fi
  
  # Push to registry if specified
  if [[ -n "$registry" ]]; then
    local tagged_image="${registry}/${image_name}:latest"
    echo "📤 Tagging and pushing to $registry..."
    docker tag "$image_name" "$tagged_image"
    docker push "$tagged_image"
    echo "$tagged_image"
  else
    echo "$image_name"
  fi
}

# Deploy Cloud AI pod
deploy() {
  local name="${1:-$DEFAULT_CONTAINER_NAME}"
  local namespace="${2:-$DEFAULT_NAMESPACE}"
  local image="${3:-$DEFAULT_IMAGE}"
  local workspace_pvc="${4:-cloud-ai-workspace}"
  
  check_kubectl || return 1
  ensure_namespace "$namespace"
  
  echo "🚀 Deploying Cloud AI to Kubernetes..."
  echo "   Name: $name"
  echo "   Namespace: $namespace"
  echo "   Image: $image"
  echo ""
  
  # Build environment variables from config
  local env_vars=""
  
  # Add AI provider API keys
  for key in ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY CUSTOM_AI_API_KEY CUSTOM_AI_API_ENDPOINT; do
    if [[ -n "${!key:-}" ]]; then
      env_vars="$env_vars
            - name: $key
              valueFrom:
                secretKeyRef:
                  name: cloud-ai-secrets
                  key: $key"
    fi
  done
  
  # Create secrets if needed
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]] || [[ -n "${OPENAI_API_KEY:-}" ]] || [[ -n "${GOOGLE_API_KEY:-}" ]]; then
    "$KUBECTL_BINARY" create secret generic cloud-ai-secrets \
      --from-literal=ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
      --from-literal=OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
      --from-literal=GOOGLE_API_KEY="${GOOGLE_API_KEY:-}" \
      --from-literal=CUSTOM_AI_API_KEY="${CUSTOM_AI_API_KEY:-}" \
      --from-literal=CUSTOM_AI_API_ENDPOINT="${CUSTOM_AI_API_ENDPOINT:-}" \
      --namespace="$namespace" \
      --dry-run=client -o yaml | "$KUBECTL_BINARY" apply -f -
  fi
  
  # Create PVC if not exists
  "$KUBECTL_BINARY" get pvc "$workspace_pvc" --namespace="$namespace" &>/dev/null || \
    "$KUBECTL_BINARY" apply -f - --namespace="$namespace" <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $workspace_pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF
  
  # Deploy pod
  "$KUBECTL_BINARY" apply -f - --namespace="$namespace" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $name
  labels:
    app: cloud-ai
spec:
  containers:
  - name: cloud-ai
    image: $image
    command: ["tail", "-f", "/dev/null"]
    env:
      - name: CLOUD_AI_ROOT
        value: /workspace/.cloud-ai
      - name: CLOUD_AI_RUNTIME
        value: kubernetes
      - name: WORKSPACE_MOUNT
        value: /workspace
$env_vars
    volumeMounts:
    - name: workspace
      mountPath: /workspace
    resources:
      requests:
        memory: "512Mi"
        cpu: "500m"
      limits:
        memory: "4Gi"
        cpu: "2000m"
  volumes:
  - name: workspace
    persistentVolumeClaim:
      claimName: $workspace_pvc
EOF
  
  echo ""
  echo "✅ Pod deployed: $name"
  echo ""
  echo "📋 Wait for pod to be ready:"
  echo "   kubectl wait --for=condition=Ready pod/$name -n $namespace --timeout=60s"
  echo ""
  echo "📋 To connect to the pod:"
  echo "   kubectl exec -it $name -n $namespace -- bash"
}

# Delete pod
delete_pod() {
  local name="${1:-$DEFAULT_CONTAINER_NAME}"
  local namespace="${2:-$DEFAULT_NAMESPACE}"
  
  check_kubectl || return 1
  
  echo "🗑️  Deleting Cloud AI pod: $name"
  "$KUBECTL_BINARY" delete pod "$name" --namespace="$namespace" --ignore-not-found
}

# Execute command in pod
exec_in_pod() {
  local name="${1:-$DEFAULT_CONTAINER_NAME}"
  local namespace="${2:-$DEFAULT_NAMESPACE}"
  shift 2
  local cmd="$*"
  
  check_kubectl || return 1
  
  "$KUBECTL_BINARY" exec -it "$name" --namespace="$namespace" -- bash -c "$cmd"
}

# Run Cloud AI autonomously in pod
run_autonomous() {
  local name="${1:-$DEFAULT_CONTAINER_NAME}"
  local prompt="${2:-}"
  local max_iterations="${3:-0}"
  local completion_promise="${4:-}"
  
  if [[ -z "$prompt" ]]; then
    echo "❌ Error: Prompt required for autonomous execution"
    echo "Usage: kubernetes-runtime run-autonomous <pod> <prompt> [max_iterations] [completion_promise]"
    return 1
  fi
  
  echo "🔄 Starting autonomous execution in Kubernetes..."
  echo "   Pod: $name"
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
  
  # Execute in pod
  exec_in_pod "$name" "cd /workspace && $ralph_cmd"
}

# Get pod status
status() {
  local name="${1:-$DEFAULT_CONTAINER_NAME}"
  local namespace="${2:-$DEFAULT_NAMESPACE}"
  
  check_kubectl || return 1
  
  echo "📊 Kubernetes Cloud AI Status"
  echo "=============================="
  echo ""
  
  echo "Namespace: $namespace"
  echo ""
  
  echo "Pods:"
  "$KUBECTL_BINARY" get pods --namespace="$namespace" -l app=cloud-ai -o wide || echo "  No Cloud AI pods found"
  
  echo ""
  echo "PVCs:"
  "$KUBECTL_BINARY" get pvc --namespace="$namespace" -l app=cloud-ai 2>/dev/null || echo "  No PVCs found"
  
  echo ""
  echo "Secrets:"
  "$KUBECTL_BINARY" get secrets --namespace="$namespace" cloud-ai-secrets 2>/dev/null || echo "  No secrets configured"
}

# Show help
show_help() {
  cat << 'HELP_EOF'
Kubernetes Runtime Adapter

USAGE:
  kubernetes-runtime <command> [arguments]

COMMANDS:
  deploy [name] [namespace] [image] [pvc-name]
    Deploy Cloud AI pod to Kubernetes
    
  delete [name] [namespace]
    Delete a Cloud AI pod
    
  exec <pod> <namespace> <command>
    Execute a command in a pod
    
  run-autonomous <pod> <prompt> [max_iterations] [completion_promise]
    Run Cloud AI autonomously using Ralph loop
    
  status [pod] [namespace]
    Show pod status
    
  build [image-name] [registry] [dockerfile]
    Build and optionally push Cloud AI image
    
  help
    Show this help message

ENVIRONMENT VARIABLES:
  K8S_NAMESPACE         Default namespace (default: cloud-ai)
  ANTHROPIC_API_KEY     Anthropic API key (stored as secret)
  OPENAI_API_KEY        OpenAI API key (stored as secret)
  GOOGLE_API_KEY        Google API key (stored as secret)
  CUSTOM_AI_API_KEY     Custom AI API key (stored as secret)

EXAMPLES:
  # Deploy with defaults
  kubernetes-runtime deploy
  
  # Deploy with custom settings
  kubernetes-runtime deploy my-cloud-ai production my-registry/cloud-ai:latest
  
  # Run autonomous task
  kubernetes-runtime run-autonomous cloud-ai-runtime "Build REST API" 50 "DONE"
  
  # Execute commands
  kubernetes-runtime exec cloud-ai-runtime cloud-ai "cd /workspace && npm install"
  
  # Check status
  kubernetes-runtime status

NOTES:
  - Requires kubectl configured with cluster access
  - Creates namespace, PVC, secrets, and pod automatically
  - Secrets are created from environment variables
  - Pod runs with resource limits (512Mi-4Gi RAM, 500m-2000m CPU)
HELP_EOF
}

# Main command handler
case "${1:-help}" in
  deploy)
    shift
    deploy "$@"
    ;;
  delete)
    shift
    delete_pod "$@"
    ;;
  exec)
    shift
    exec_in_pod "$@"
    ;;
  run-autonomous)
    shift
    run_autonomous "$@"
    ;;
  status)
    shift
    status "$@"
    ;;
  build)
    shift
    build_image "$@"
    ;;
  help|*)
    show_help
    ;;
esac
