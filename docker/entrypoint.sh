#!/bin/bash
# LLM Workflow Toolkit - Container Entrypoint
# Handles initialization and runs llmup or custom commands

set -e

# Configuration
WORKFLOW_ROOT="/opt/llm-workflow"
MODULE_PATH="/root/.local/share/powershell/Modules/LLMWorkflow"
PALACE_PATH="${MEMPALACE_PALACE_PATH:-/data/mempalace}"

# Colors for output (only if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# Logging functions
log_info() {
    echo -e "${BLUE}[llm-workflow]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[llm-workflow]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[llm-workflow]${NC} $1"
}

log_error() {
    echo -e "${RED}[llm-workflow]${NC} $1"
}

# Check if running in container
check_container_env() {
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
        log_info "Running in container environment"
        return 0
    fi
    # Alternative check for containerized environments
    if [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
        log_info "Running in Kubernetes environment"
        return 0
    fi
    return 1
}

# Initialize workspace directory
init_workspace() {
    local workspace="${1:-/workspace}"
    
    log_info "Initializing workspace: $workspace"
    
    # Ensure workspace exists
    if [ ! -d "$workspace" ]; then
        log_warn "Workspace directory does not exist, creating: $workspace"
        mkdir -p "$workspace"
    fi
    
    # Ensure it's writable
    if [ ! -w "$workspace" ]; then
        log_error "Workspace directory is not writable: $workspace"
        return 1
    fi
    
    # Create necessary subdirectories
    mkdir -p "$workspace/.memorybridge"
    mkdir -p "$workspace/.contextlattice"
    
    log_success "Workspace initialized"
}

# Initialize MemPalace data directory
init_mempalace() {
    log_info "Initializing MemPalace at: $PALACE_PATH"
    
    mkdir -p "$PALACE_PATH"
    
    if [ ! -w "$PALACE_PATH" ]; then
        log_error "MemPalace directory is not writable: $PALACE_PATH"
        return 1
    fi
    
    log_success "MemPalace initialized"
}

# Verify Python dependencies
verify_python_deps() {
    log_info "Verifying Python dependencies..."
    
    # Check chromadb
    if python -c "import chromadb" 2>/dev/null; then
        log_success "ChromaDB is available"
    else
        log_error "ChromaDB is not installed"
        return 1
    fi
    
    # Check codemunch-pro
    if command -v codemunch-pro >/dev/null 2>&1; then
        log_success "codemunch-pro is available"
    else
        log_warn "codemunch-pro command not found, will attempt install"
        python -m pip install --quiet codemunch-pro || {
            log_error "Failed to install codemunch-pro"
            return 1
        }
    fi
    
    return 0
}

# Verify PowerShell module
verify_powershell_module() {
    log_info "Verifying PowerShell module..."
    
    pwsh -NoProfile -Command "
        try {
            Import-Module LLMWorkflow -Force -ErrorAction Stop
            Write-Host 'LLMWorkflow module loaded successfully'
            exit 0
        } catch {
            Write-Error "Failed to load LLMWorkflow module: \$_"
            exit 1
        }
    " || {
        log_error "PowerShell module verification failed"
        return 1
    }
    
    log_success "PowerShell module verified"
}

# Load environment from mounted .env files
load_env_files() {
    local workspace="${1:-/workspace}"
    
    # Load .env from workspace if exists
    if [ -f "$workspace/.env" ]; then
        log_info "Loading environment from $workspace/.env"
        set -a
        # shellcheck source=/dev/null
        . "$workspace/.env"
        set +a
    fi
    
    # Load orchestrator.env if exists
    if [ -f "$workspace/.contextlattice/orchestrator.env" ]; then
        log_info "Loading environment from $workspace/.contextlattice/orchestrator.env"
        set -a
        # shellcheck source=/dev/null
        . "$workspace/.contextlattice/orchestrator.env"
        set +a
    fi
}

# Display help
show_help() {
    cat << 'EOF'
LLM Workflow Toolkit - Container Usage

Commands:
  llmup, up              Run llmup workflow bootstrap (default)
  llmcheck, check        Run setup validation
  llmver, version        Show version information
  llmdown, uninstall     Uninstall workflow
  llmupdate, update      Update workflow module
  doctor                 Run diagnostics
  shell, bash            Start bash shell
  pwsh, powershell       Start PowerShell
  help                   Show this help message

Environment Variables:
  OPENAI_API_KEY         OpenAI API key
  ANTHROPIC_API_KEY      Anthropic/Claude API key
  KIMI_API_KEY           Moonshot/Kimi API key
  GEMINI_API_KEY         Google Gemini API key
  GLM_API_KEY            Zhipu GLM API key
  CONTEXTLATTICE_ORCHESTRATOR_URL    ContextLattice URL
  CONTEXTLATTICE_ORCHESTRATOR_API_KEY  ContextLattice API key
  MEMPALACE_PALACE_PATH  MemPalace data directory

Volumes:
  /workspace             Project workspace (mount your project here)
  /data/mempalace        MemPalace persistent storage

Examples:
  # Run llmup in current directory
  docker run -v $(pwd):/workspace llm-workflow

  # Run with API key
  docker run -v $(pwd):/workspace -e OPENAI_API_KEY=sk-xxx llm-workflow

  # Interactive shell
  docker run -it -v $(pwd):/workspace llm-workflow shell

  # With docker-compose
  docker-compose up llm-workflow
EOF
}

# Main entrypoint logic
main() {
    log_info "LLM Workflow Toolkit Container v0.9.6"
    
    # Check container environment
    check_container_env || log_warn "May not be running in container"
    
    # Initialize directories
    init_workspace "/workspace"
    init_mempalace
    
    # Load environment files
    load_env_files "/workspace"
    
    # Verify dependencies
    verify_python_deps || exit 1
    verify_powershell_module || exit 1
    
    # Handle command
    case "${1:-}" in
        llmup|up|"")
            log_info "Running llmup..."
            cd /workspace
            exec pwsh -NoProfile -Command "llmup"
            ;;
        llmcheck|check)
            log_info "Running llmcheck..."
            cd /workspace
            exec pwsh -NoProfile -Command "llmcheck"
            ;;
        llmver|version)
            exec pwsh -NoProfile -Command "llmver"
            ;;
        llmdown|uninstall)
            log_info "Running llmdown..."
            exec pwsh -NoProfile -Command "llmdown"
            ;;
        llmupdate|update)
            log_info "Running llmupdate..."
            exec pwsh -NoProfile -Command "llmupdate"
            ;;
        doctor)
            log_info "Running diagnostics..."
            cd /workspace
            exec pwsh -NoProfile -Command "Test-LLMWorkflowSetup -CheckConnectivity"
            ;;
        shell|bash|sh)
            log_info "Starting bash shell..."
            exec /bin/bash
            ;;
        pwsh|powershell)
            log_info "Starting PowerShell..."
            exec pwsh
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        *)
            # Pass through to PowerShell
            log_info "Executing: $@"
            exec pwsh -NoProfile -Command "$@"
            ;;
    esac
}

# Run main function
main "$@"

