# Cloud AI - Autonomous Cloud Platform

Transform Claude Code into an autonomous Cloud AI application with injectable AI providers and runtime environments.

## 🚀 Features

### Injectable AI Providers
- **Anthropic** - Claude models (default)
- **OpenAI** - GPT-4o, GPT-4 Turbo, o1 models
- **Google** - Gemini 1.5 Pro/Flash
- **Custom** - Any OpenAI-compatible API (Ollama, LocalAI, vLLM)

### Runtime Environments
- **Docker** - Local containers with network isolation
- **GitHub Codespaces** - Cloud development environments
- **Tripod** - Custom cloud provider adapter
- **Kubernetes** - Production cluster deployment

### Autonomous Execution
- Ralph Wiggum technique for iterative self-correction
- Configurable max iterations or completion promise detection
- State persistence across sessions
- Network isolation and security boundaries

## 📁 Structure

```
.cloud-ai/
├── cloud-ai.sh           # Main orchestrator
├── .claude-plugin/       # Plugin definition
├── config/
│   └── provider-config.json  # Provider & runtime settings
├── providers/            # AI provider implementations
│   ├── anthropic.sh
│   ├── openai.sh
│   ├── google.sh
│   └── custom.sh
├── runtimes/             # Runtime adapters
│   ├── docker.sh
│   ├── github-codespaces.sh
│   ├── tripod.sh
│   └── kubernetes.sh
├── commands/             # Slash commands
│   ├── deploy.md
│   ├── configure-provider.md
│   ├── run-autonomous.md
│   ├── switch-runtime.md
│   └── cloud-status.md
├── hooks/                # Session hooks
│   └── session-start.sh
└── mcp/                  # MCP servers (extend here)
```

## 🔧 Quick Start

### 1. Initialize
```bash
cd /workspace
export CLOUD_AI_ROOT=/workspace/.cloud-ai
./.cloud-ai/cloud-ai.sh init
```

### 2. Configure Provider
```bash
# Using slash commands in Claude
/configure-provider anthropic sk-ant-your-api-key

# Or via environment
export ANTHROPIC_API_KEY=sk-ant-...
```

### 3. Deploy Runtime
```bash
# Deploy to Docker (default)
/deploy docker

# Deploy to GitHub Codespaces
/deploy github-codespaces

# Deploy to Kubernetes
/deploy kubernetes
```

### 4. Run Autonomous Task
```bash
/run-autonomous "Build a REST API for todos" anthropic docker 50 "API complete"
```

## 📖 Commands

| Command | Description |
|---------|-------------|
| `/deploy <runtime>` | Deploy to Docker, Codespaces, Tripod, or Kubernetes |
| `/configure-provider <provider> <key> [endpoint]` | Configure AI provider |
| `/run-autonomous "<prompt>" [provider] [runtime] [max_iter] [promise]` | Run autonomous task |
| `/switch-runtime <runtime>` | Change default runtime |
| `/cloud-status` | Show status of all providers and runtimes |

## 🔐 Provider Configuration

### Anthropic (Default)
```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

### OpenAI
```bash
export OPENAI_API_KEY=sk-...
/cloud-ai.sh switch-provider openai
```

### Google
```bash
export GOOGLE_API_KEY=...
```

### Custom (Ollama Example)
```bash
export CUSTOM_AI_API_ENDPOINT=http://localhost:11434/v1
export CUSTOM_AI_API_KEY=ollama
/cloud-ai.sh configure custom ollama http://localhost:11434/v1
```

## 🖥️ Runtime Details

### Docker
- Network isolation via iptables
- Persistent volumes
- CAP_NET_ADMIN for firewall

### GitHub Codespaces
- Requires `gh` CLI
- SSH-based execution
- Auto-creates codespace

### Kubernetes
- Creates namespace, PVC, secrets
- Resource limits configured
- Production-ready deployment

## 🔄 Ralph Loop Autonomy

The autonomous execution uses the Ralph Wiggum technique:

1. AI receives prompt and starts working
2. On exit attempt, stop hook intercepts
3. Same prompt is fed back with iteration count
4. Loop continues until:
   - Max iterations reached, OR
   - Completion promise detected: `<promise>DONE</promise>`

### Example
```bash
/run-autonomous "Fix all bugs in auth module" anthropic docker 0 "All tests passing"
```

## 🛡️ Security

- API keys stored as environment variables or Kubernetes secrets
- Network isolation per runtime
- Container/pod resource limits
- No outbound access without explicit allow

## 📝 Configuration File

Edit `.cloud-ai/config/provider-config.json`:

```json
{
  "default_provider": "anthropic",
  "providers": {
    "anthropic": {
      "enabled": true,
      "models": {
        "default": "claude-sonnet-4-5-20250929"
      }
    }
  },
  "runtime": {
    "default": "docker"
  },
  "autonomy": {
    "max_iterations": 0,
    "state_persistence": true
  }
}
```

## 🔌 Extending

### Add New Provider
1. Create `.cloud-ai/providers/myprovider.sh`
2. Implement: `complete`, `validate`, `models` functions
3. Add config entry in `provider-config.json`

### Add New Runtime
1. Create `.cloud-ai/runtimes/myruntime.sh`
2. Implement: `deploy`, `exec_in_runtime`, `run_autonomous`
3. Register in plugin.json

### Add MCP Server
1. Create `.cloud-ai/mcp/myserver/`
2. Follow MCP protocol specification
3. Reference in commands

## 🎯 Use Cases

- **Autonomous Development**: "Build a complete CRUD API"
- **Code Migration**: "Migrate from Express to Fastify"
- **Bug Fixing**: "Fix all memory leaks with promise: 'No memory issues'"
- **Testing**: "Write tests until coverage > 80%"
- **Documentation**: "Document all public APIs"

## 📚 Related

- [Ralph Wiggum Plugin](../plugins/ralph-wiggum/) - Core autonomy engine
- [Hookify](../plugins/hookify/) - Hook management
- [Claude Code Docs](https://docs.anthropic.com/claude-code/)
