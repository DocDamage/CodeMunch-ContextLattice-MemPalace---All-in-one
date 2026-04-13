# Docker Containerization Guide

Complete guide for running LLM Workflow Toolkit in Docker containers.

## Table of Contents

- [Quick Start](#quick-start)
- [Image Variants](#image-variants)
- [Docker Compose](#docker-compose)
- [Environment Variables](#environment-variables)
- [Volume Mounts](#volume-mounts)
- [CI/CD Integration](#cicd-integration)
- [Troubleshooting](#troubleshooting)

## Quick Start

### Build the Image

```bash
# Linux containers (default)
docker build -t llm-workflow .

# Windows containers
docker build -f Dockerfile.windows -t llm-workflow:windows .
```

### Basic Usage

```bash
# Run llmup in current directory
docker run -v $(pwd):/workspace -e OPENAI_API_KEY llm-workflow

# Run with multiple API keys
docker run -v $(pwd):/workspace \
  -e OPENAI_API_KEY \
  -e ANTHROPIC_API_KEY \
  -e KIMI_API_KEY \
  llm-workflow

# Interactive shell
docker run -it -v $(pwd):/workspace llm-workflow shell
```

## Image Variants

| Tag | Description | Base Image |
|-----|-------------|------------|
| `latest` | Linux container with PowerShell | `mcr.microsoft.com/powershell:latest` |
| `windows` | Windows Server Core container | `mcr.microsoft.com/powershell:windowsservercore-ltsc2022` |

## Docker Compose

### Basic Setup

```bash
# Start services
docker-compose up -d

# Run workflow
docker-compose run --rm llm-workflow

# Stop services
docker-compose down
```

### With Optional Ollama

```bash
# Start with Ollama for local LLM inference
docker-compose --profile ollama up -d

# Pull a model
docker-compose exec ollama ollama pull llama3
```

### Custom Configuration

Create `docker-compose.override.yml`:

```yaml
version: "3.8"
services:
  llm-workflow:
    environment:
      - LLM_PROVIDER=ollama
      - OLLAMA_BASE_URL=http://ollama:11434
```

## Environment Variables

### API Keys

| Variable | Provider | Example |
|----------|----------|---------|
| `OPENAI_API_KEY` | OpenAI | `sk-...` |
| `ANTHROPIC_API_KEY` | Claude | `sk-ant-...` |
| `KIMI_API_KEY` | Moonshot | `sk-...` |
| `GEMINI_API_KEY` | Google | `...` |
| `GLM_API_KEY` | Zhipu | `...` |
| `OLLAMA_API_KEY` | Ollama | (optional) |

### ContextLattice Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTEXTLATTICE_ORCHESTRATOR_URL` | `http://contextlattice:8075` | Orchestrator endpoint |
| `CONTEXTLATTICE_ORCHESTRATOR_API_KEY` | - | API key for authentication |

### MemPalace Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `MEMPALACE_PALACE_PATH` | `/data/mempalace` | ChromaDB storage path |

### Provider URLs (optional)

| Variable | Default |
|----------|---------|
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` |
| `ANTHROPIC_BASE_URL` | `https://api.anthropic.com/v1` |
| `KIMI_BASE_URL` | `https://api.moonshot.cn/v1` |
| `GEMINI_BASE_URL` | `https://generativelanguage.googleapis.com/v1beta/openai` |
| `GLM_BASE_URL` | `https://open.bigmodel.cn/api/paas/v4` |
| `OLLAMA_BASE_URL` | `http://host.docker.internal:11434` |

### Other Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `LLM_PROVIDER` | `openai` | Default provider preference |
| `LLM_WORKFLOW_LOG_LEVEL` | `INFO` | Logging verbosity |

## Volume Mounts

### Required

```bash
-v $(pwd):/workspace          # Your project files
```

### Optional

```bash
-v mempalace-data:/data/mempalace  # Persistent ChromaDB storage
-v /path/to/.env:/workspace/.env:ro # Environment file
```

## CI/CD Integration

### GitHub Actions

```yaml
name: LLM Workflow

on: [push, pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    container:
      image: llm-workflow:latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run LLM Workflow
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
        run: llmup
      
      - name: Validate
        run: llmcheck
```

### GitLab CI

```yaml
llm-workflow:
  image: llm-workflow:latest
  script:
    - llmup
    - llmcheck
  variables:
    OPENAI_API_KEY: $OPENAI_API_KEY
```

### Azure DevOps

```yaml
pool:
  vmImage: 'ubuntu-latest'

container: llm-workflow:latest

steps:
- script: |
    llmup
    llmcheck
  env:
    OPENAI_API_KEY: $(OPENAI_API_KEY)
```

### Jenkins

```groovy
pipeline {
    agent {
        docker {
            image 'llm-workflow:latest'
            args '-v $WORKSPACE:/workspace -e OPENAI_API_KEY'
        }
    }
    stages {
        stage('LLM Workflow') {
            steps {
                sh 'llmup'
            }
        }
    }
}
```

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker logs llm-workflow

# Verify image
docker run --rm llm-workflow llmver
```

### Permission Issues

```bash
# Run as current user (Linux)
docker run -u $(id -u):$(id -g) -v $(pwd):/workspace llm-workflow

# Fix permissions in container
docker run -v $(pwd):/workspace llm-workflow shell -c "chown -R $(id -u):$(id -g) /workspace"
```

### Python/Module Not Found

```bash
# Reinstall Python dependencies
docker run -v $(pwd):/workspace llm-workflow shell -c "
  pip install --upgrade chromadb codemunch-pro
"

# Verify PowerShell module
docker run --rm llm-workflow pwsh -Command "Get-Module LLMWorkflow -ListAvailable"
```

### Network Issues

```bash
# Test connectivity to ContextLattice
docker run --rm llm-workflow shell -c "
  curl -f http://contextlattice:8075/health
"

# Check Ollama connection
docker run --rm llm-workflow shell -c "
  curl -f http://host.docker.internal:11434/api/tags
"
```

### Windows Container Issues

```powershell
# Switch to Windows containers
docker context use default

# Build Windows image
docker build -f Dockerfile.windows -t llm-workflow:windows .

# Run Windows container
docker run -v "${PWD}:C:\workspace" llm-workflow:windows
```

## Development

### Building Locally

```bash
# Build with no cache
docker build --no-cache -t llm-workflow .

# Build specific stage
docker build --target base -t llm-workflow:base .
```

### Testing Changes

```bash
# Mount local code for testing
docker run -v $(pwd):/opt/llm-workflow:ro -v $(pwd):/workspace llm-workflow
```

### Multi-arch Build

```bash
# Build for multiple platforms
docker buildx create --use
docker buildx build --platform linux/amd64,linux/arm64 -t llm-workflow:latest --push .
```
