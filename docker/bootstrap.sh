#!/bin/bash
# LLM Workflow Toolkit - Container Bootstrap Script
# Runs inside container to set up the environment

set -e

WORKFLOW_ROOT="/opt/llm-workflow"
PALACE_PATH="${MEMPALACE_PALACE_PATH:-/data/mempalace}"

echo "[llm-workflow] Bootstrapping container environment..."

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install Python package if missing
ensure_python_package() {
    local package="$1"
    local import_name="${2:-$package}"
    
    if python -c "import $import_name" 2>/dev/null; then
        echo "[llm-workflow] Python package '$package' is already installed"
        return 0
    fi
    
    echo "[llm-workflow] Installing Python package: $package"
    python -m pip install --upgrade "$package"
}

# Function to ensure directory exists
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo "[llm-workflow] Creating directory: $dir"
        mkdir -p "$dir"
    fi
}

# Bootstrap Python environment
echo "[llm-workflow] Setting up Python environment..."

# Ensure pip is up to date
python -m pip install --upgrade pip setuptools wheel

# Install required packages
ensure_python_package "chromadb" "chromadb"
ensure_python_package "codemunch-pro" "codemunch"

# Verify installations
echo "[llm-workflow] Verifying Python packages..."
python -c "import chromadb; print(f'ChromaDB: {chromadb.__version__}')"
codemunch-pro --version 2>/dev/null || echo "codemunch-pro installed"

# Bootstrap PowerShell module
echo "[llm-workflow] Setting up PowerShell module..."

MODULE_BASE="/root/.local/share/powershell/Modules"
MODULE_NAME="LLMWorkflow"
MODULE_VERSION="0.2.0"
MODULE_PATH="$MODULE_BASE/$MODULE_NAME/$MODULE_VERSION"

if [ -d "$MODULE_PATH" ]; then
    echo "[llm-workflow] PowerShell module already installed at: $MODULE_PATH"
else
    echo "[llm-workflow] Installing PowerShell module to: $MODULE_PATH"
    ensure_dir "$MODULE_PATH"
    cp -r "$WORKFLOW_ROOT/module/LLMWorkflow/"* "$MODULE_PATH/"
fi

# Verify PowerShell module
echo "[llm-workflow] Verifying PowerShell module..."
pwsh -NoProfile -Command "
    Import-Module LLMWorkflow -Force
    Get-Module LLMWorkflow | Select-Object Name, Version
"

# Bootstrap directories
echo "[llm-workflow] Setting up directories..."
ensure_dir "/workspace"
ensure_dir "$PALACE_PATH"
ensure_dir "/workspace/.memorybridge"
ensure_dir "/workspace/.contextlattice"

# Create default .env file if not exists
if [ ! -f "/workspace/.env" ]; then
    echo "[llm-workflow] Creating default .env file..."
    cat > /workspace/.env << 'EOF'
# LLM Workflow Toolkit - Environment Configuration
# Add your API keys here or mount an existing .env file

# OpenAI
# OPENAI_API_KEY=your-key-here

# Anthropic Claude
# ANTHROPIC_API_KEY=your-key-here

# Moonshot Kimi
# KIMI_API_KEY=your-key-here

# Google Gemini
# GEMINI_API_KEY=your-key-here

# Zhipu GLM
# GLM_API_KEY=your-key-here
# GLM_BASE_URL=https://open.bigmodel.cn/api/paas/v4

# ContextLattice
CONTEXTLATTICE_ORCHESTRATOR_URL=http://contextlattice:8075
# CONTEXTLATTICE_ORCHESTRATOR_API_KEY=your-key-here

# MemPalace
MEMPALACE_PALACE_PATH=/data/mempalace
EOF
fi

echo "[llm-workflow] Bootstrap complete!"
echo "[llm-workflow] Available commands: llmup, llmcheck, llmver, llmdown"
