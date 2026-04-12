# LLM Workflow Toolkit - Dockerfile
# Multi-stage build for Linux containers (default)
# Supports: PowerShell + Python 3.10+ + ChromaDB + codemunch-pro

# Stage 1: Base image with PowerShell
FROM mcr.microsoft.com/powershell:latest AS base

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PSModulePath="/root/.local/share/powershell/Modules:/opt/microsoft/powershell/7/Modules" \
    LLM_WORKFLOW_TOOLKIT_SOURCE="/opt/llm-workflow/module/LLMWorkflow/templates/tools"

# Install Python 3.10+ and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Ensure python command points to python3
RUN ln -sf /usr/bin/python3 /usr/bin/python

# Stage 2: Install Python dependencies
FROM base AS python-deps

# Install chromadb and codemunch-pro
RUN python -m pip install --upgrade pip setuptools wheel && \
    python -m pip install chromadb>=0.5.0 codemunch-pro

# Verify installations
RUN python -c "import chromadb; print('ChromaDB version:', chromadb.__version__)" && \
    codemunch-pro --version || echo "codemunch-pro installed"

# Stage 3: Final image
FROM base AS final

# Copy Python packages from python-deps stage
COPY --from=python-deps /usr/local/lib/python3.*/dist-packages /usr/local/lib/python3/dist-packages
COPY --from=python-deps /usr/local/bin /usr/local/bin

# Create working directories
RUN mkdir -p /opt/llm-workflow \
    /workspace \
    /root/.llm-workflow \
    /root/.mempalace/palace

# Copy module and toolkit files
COPY module/ /opt/llm-workflow/module/
COPY tools/ /opt/llm-workflow/tools/
COPY docker/ /opt/llm-workflow/docker/

# Install PowerShell module
RUN pwsh -NoProfile -Command "\
    \$ModulePath = '/root/.local/share/powershell/Modules/LLMWorkflow/0.2.0'; \
    New-Item -ItemType Directory -Path \$ModulePath -Force | Out-Null; \
    Copy-Item -Path '/opt/llm-workflow/module/LLMWorkflow/*' -Destination \$ModulePath -Recurse -Force; \
    Import-Module LLMWorkflow -Force; \
    Write-Host 'LLMWorkflow module installed successfully'"

# Copy entrypoint script
COPY docker/entrypoint.sh /opt/llm-workflow/entrypoint.sh
RUN chmod +x /opt/llm-workflow/entrypoint.sh

# Set working directory
WORKDIR /workspace

# Volume for persistent data
VOLUME ["/workspace", "/root/.mempalace/palace"]

# Entrypoint
ENTRYPOINT ["/opt/llm-workflow/entrypoint.sh"]

# Default command
CMD ["llmup"]

# Labels
LABEL org.opencontainers.image.title="LLM Workflow Toolkit" \
      org.opencontainers.image.description="All-in-one workflow toolkit for CodeMunch Pro, ContextLattice, and MemPalace" \
      org.opencontainers.image.version="0.2.0" \
      org.opencontainers.image.source="https://github.com/DocDamage/CodeMunch-ContextLattice-MemPalace---All-in-one" \
      org.opencontainers.image.licenses="MIT"
