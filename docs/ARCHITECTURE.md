# LLM Workflow Architecture

This document provides detailed architectural diagrams and explanations of the CodeMunch + ContextLattice + MemPalace integrated workflow system.

## Table of Contents

- [Overview](#overview)
- [Main Architecture Flowchart](#main-architecture-flowchart)
- [Detailed Component Diagram](#detailed-component-diagram)
- [Data Flow Diagram](#data-flow-diagram)
- [Provider Resolution Flow](#provider-resolution-flow)
- [Sync Process Flow](#sync-process-flow)
- [Component Details](#component-details)

---

## Overview

The LLM Workflow is a unified toolkit that integrates three core components:

- **CodeMunch**: Project indexing and MCP wrapper setup
- **ContextLattice**: Project bootstrap and connectivity verification
- **MemPalace**: Vector storage with incremental bridge to ContextLattice

---

## Main Architecture Flowchart

The high-level workflow from the user's perspective:

```mermaid
graph LR
    A([User]) --> B["llmup / Invoke-LLMWorkflowUp"]
    B --> C[Bootstrap Phase]
    C --> D[CodeMunch Index]
    C --> E[ContextLattice Verify]
    C --> F[MemPalace Bridge Sync]
    D --> G["MCP Server<br/>codemunch-pro"]
    E --> H[(ContextLattice API)]
    F --> I[(ChromaDB Palace)]
    F --> H
    
    style A fill:#e1f5fe
    style B fill:#fff3e0
    style C fill:#e8f5e9
    style D fill:#f3e5f5
    style E fill:#f3e5f5
    style F fill:#f3e5f5
    style G fill:#ffebee
    style H fill:#ffebee
    style I fill:#ffebee
```

### Flow Description

1. **User** invokes `llmup` (alias for `Invoke-LLMWorkflowUp`)
2. **Bootstrap Phase** initializes all three toolchains
3. **CodeMunch Index** creates searchable project index via MCP server
4. **ContextLattice Verify** checks connectivity to the orchestrator API
5. **MemPalace Bridge Sync** synchronizes vector data to ContextLattice

---

## Detailed Component Diagram

Complete system architecture showing all components and their relationships:

```mermaid
graph TB
    subgraph UserLayer["User Interface Layer"]
        A1[llmup]
        A2[llmcheck]
        A3[llmdown]
        A4[llmupdate]
        A5[llm-workflow-doctor]
    end
    
    subgraph ModuleLayer["PowerShell Module Layer<br/>LLMWorkflow"]
        B1[Invoke-LLMWorkflowUp]
        B2[Test-LLMWorkflowSetup]
        B3[Uninstall-LLMWorkflow]
        B4[Update-LLMWorkflow]
        B5[Resolve-ProviderProfile]
        B6[Get-ProviderProfile]
    end
    
    subgraph BootstrapLayer["Bootstrap Scripts"]
        C1[bootstrap-llm-workflow.ps1]
    end
    
    subgraph Toolchains["Tool Chains"]
        direction TB
        
        subgraph CodeMunch["CodeMunch Chain"]
            D1[bootstrap-project.ps1]
            D2[index-project.ps1]
            D3[codemunch-pro CLI]
        end
        
        subgraph ContextLattice["ContextLattice Chain"]
            E1[bootstrap-project.ps1]
            E2[verify.ps1]
            E3[orchestrator.env loader]
        end
        
        subgraph MemoryBridge["MemPalace Bridge"]
            F1[bootstrap-project.ps1]
            F2[sync-from-mempalace.ps1]
            F3[Python Bridge]
        end
    end
    
    subgraph ExternalServices["External Services"]
        G1[(ChromaDB<br/>PersistentClient)]
        G2[ContextLattice API<br/>REST Endpoints]
        G3[MCP Server]
        G4[GitHub Releases<br/>Update Source]
    end
    
    subgraph Providers["LLM Providers"]
        H1[OpenAI]
        H2[Claude/Anthropic]
        H3[Kimi/Moonshot]
        H4[Google Gemini]
        H5[GLM/Zhipu]
        H6[Ollama/Local]
    end
    
    subgraph Config["Configuration"]
        I1[.env]
        I2[.contextlattice/orchestrator.env]
        I3[.memorybridge/bridge.config.json]
        I4[.memorybridge/sync-state.json]
    end
    
    A1 --> B1
    A2 --> B2
    A3 --> B3
    A4 --> B4
    
    B1 --> C1
    B5 --> Providers
    
    C1 --> D1
    C1 --> E1
    C1 --> F1
    
    D1 --> D2 --> D3 --> G3
    E1 --> E2 --> G2
    F1 --> F2 --> F3
    
    F3 --> G1
    F3 --> G2
    
    B4 --> G4
    
    I1 --> C1
    I2 --> E2
    I3 --> F3
    I4 --> F3
    
    E2 -.->|Health Check| G2
    E2 -.->|Status Check| G2
    E2 -.->|Smoke Test| G2
    
    style UserLayer fill:#e3f2fd
    style ModuleLayer fill:#e8f5e9
    style BootstrapLayer fill:#fff3e0
    style CodeMunch fill:#fce4ec
    style ContextLattice fill:#fce4ec
    style MemoryBridge fill:#fce4ec
    style ExternalServices fill:#f3e5f5
    style Providers fill:#e0f2f1
    style Config fill:#fff9c4
```

---

## Data Flow Diagram

### Primary Data Flows

```mermaid
graph LR
    subgraph Sources["Data Sources"]
        S1[Project Files]
        S2[Code Snippets]
        S3[Documentation]
    end
    
    subgraph Processing["Processing Layer"]
        P1[CodeMunch Indexer]
        P2[Embedding Generator]
    end
    
    subgraph Storage["Storage Layer"]
        ST1[(ChromaDB<br/>Vector Store)]
        ST2[.codemunch<br/>Index Files]
    end
    
    subgraph Bridge["Bridge Layer"]
        B1[Python Sync Script]
        B2[State Manager]
        B3[Batch Processor]
    end
    
    subgraph Target["Target Layer"]
        T1[(ContextLattice API)]
        T2[MCP Server]
    end
    
    S1 --> P1
    S2 --> P1
    S3 --> P1
    
    P1 --> P2
    P1 --> ST2
    
    P2 --> ST1
    
    ST1 --> B1
    B1 --> B2
    B1 --> B3
    
    B3 -->|POST /memory/write| T1
    ST2 --> T2
    
    style Sources fill:#e3f2fd
    style Processing fill:#e8f5e9
    style Storage fill:#fff3e0
    style Bridge fill:#fce4ec
    style Target fill:#f3e5f5
```

### MemPalace to ContextLattice Sync Flow

```mermaid
sequenceDiagram
    autonumber
    participant PS as PowerShell Script
    participant PY as Python Bridge
    participant Config as Config/State Files
    participant DB as ChromaDB
    participant API as ContextLattice API
    
    PS->>PY: Invoke sync-from-mempalace.ps1
    PY->>Config: Load bridge.config.json
    PY->>Config: Load sync-state.json
    PY->>DB: Initialize PersistentClient
    PY->>DB: Get Collection (mempalace_drawers)
    
    loop Batch Processing
        PY->>DB: collection.get(limit=batch_size)
        DB-->>PY: Return documents + metadata
        
        PY->>PY: Calculate content hash
        PY->>PY: Compare with sync state
        
        alt Content Changed or Force Resync
            PY->>PY: Prepare write payload
            PY->>API: POST /memory/write
            API-->>PY: Response {ok: true}
            PY->>Config: Update sync-state.json
        else Content Unchanged
            PY->>PY: Skip (increment counter)
        end
    end
    
    PY->>Config: Save final state
    PY->>Config: Append to sync-history.jsonl
    PY-->>PS: Return summary JSON
```

---

## Provider Resolution Flow

### Provider Selection Algorithm

```mermaid
flowchart TD
    Start([User Request]) --> CheckExplicit{Explicit Provider<br/>Specified?}
    
    CheckExplicit -->|Yes| UseExplicit[Use Requested Provider]
    CheckExplicit -->|No| CheckOverride{LLM_PROVIDER<br/>Env Var Set?}
    
    CheckOverride -->|Yes| ValidateOverride{Valid &<br/>Key Available?}
    CheckOverride -->|No| AutoDetect[Auto-Detection Mode]
    
    ValidateOverride -->|Yes| UseOverride[Use LLM_PROVIDER]
    ValidateOverride -->|No| AutoDetect
    
    AutoDetect --> CheckOpenAI{OPENAI_API_KEY?}
    CheckOpenAI -->|Found| UseOpenAI[Use OpenAI]
    CheckOpenAI -->|Not Found| CheckClaude{ANTHROPIC_API_KEY?}
    
    CheckClaude -->|Found| UseClaude[Use Claude]
    CheckClaude -->|Not Found| CheckKimi{KIMI_API_KEY?}
    
    CheckKimi -->|Found| UseKimi[Use Kimi]
    CheckKimi -->|Not Found| CheckGemini{GEMINI_API_KEY?}
    
    CheckGemini -->|Found| UseGemini[Use Gemini]
    CheckGemini -->|Not Found| CheckGLM{GLM_API_KEY?}
    
    CheckGLM -->|Found| UseGLM[Use GLM]
    CheckGLM -->|Not Found| CheckOllama{OLLAMA_HOST?}
    
    CheckOllama -->|Found| UseOllama[Use Ollama]
    CheckOllama -->|Not Found| NoProvider[No Provider Found]
    
    UseExplicit --> ResolveProfile[Resolve-ProviderProfile]
    UseOverride --> ResolveProfile
    UseOpenAI --> ResolveProfile
    UseClaude --> ResolveProfile
    UseKimi --> ResolveProfile
    UseGemini --> ResolveProfile
    UseGLM --> ResolveProfile
    UseOllama --> ResolveProfile
    
    ResolveProfile --> GetProfile[Get-ProviderProfile]
    GetProfile --> FindKey[Find API Key<br/>in Env Vars]
    FindKey --> FindBaseUrl[Find/Set Base URL]
    FindBaseUrl --> ReturnProfile[Return Profile Object]
    
    ReturnProfile --> End([End])
    NoProvider --> End
    
    style Start fill:#e1f5fe
    style End fill:#e1f5fe
    style UseOpenAI fill:#e8f5e9
    style UseClaude fill:#e8f5e9
    style UseKimi fill:#e8f5e9
    style UseGemini fill:#e8f5e9
    style UseGLM fill:#e8f5e9
    style UseOllama fill:#e8f5e9
    style NoProvider fill:#ffebee
```

### Provider Priority Order

```mermaid
graph LR
    A[Auto-Detection] --> B[OpenAI]
    B --> C[Claude]
    C --> D[Kimi]
    D --> E[Gemini]
    E --> F[GLM]
    F --> G[Ollama]
    
    style A fill:#fff3e0
    style B fill:#e8f5e9
    style C fill:#e8f5e9
    style D fill:#e8f5e9
    style E fill:#e8f5e9
    style F fill:#e8f5e9
    style G fill:#e8f5e9
```

### Provider Configuration Matrix

| Provider | API Key Variables | Base URL Variables | Default Base URL |
|----------|-------------------|-------------------|------------------|
| OpenAI | `OPENAI_API_KEY` | `OPENAI_BASE_URL` | `https://api.openai.com/v1` |
| Claude | `ANTHROPIC_API_KEY`, `CLAUDE_API_KEY` | `ANTHROPIC_BASE_URL`, `CLAUDE_BASE_URL` | `https://api.anthropic.com/v1` |
| Kimi | `KIMI_API_KEY`, `MOONSHOT_API_KEY` | `KIMI_BASE_URL`, `MOONSHOT_BASE_URL` | `https://api.moonshot.cn/v1` |
| Gemini | `GEMINI_API_KEY`, `GOOGLE_API_KEY` | `GEMINI_BASE_URL` | `https://generativelanguage.googleapis.com/v1beta/openai` |
| GLM | `GLM_API_KEY`, `ZHIPU_API_KEY` | `GLM_BASE_URL` | `https://open.bigmodel.cn/api/paas/v4` |
| Ollama | `OLLAMA_API_KEY` | `OLLAMA_BASE_URL`, `OLLAMA_HOST` | `http://localhost:11434/v1` |

---

## Sync Process Flow

### Incremental Sync Workflow

```mermaid
flowchart TD
    Start([Start Sync]) --> LoadConfig[Load Config Files]
    LoadConfig --> LoadState[Load sync-state.json]
    LoadState --> InitChroma[Initialize ChromaDB Client]
    
    InitChroma --> GetCollection[Get Collection<br/>mempalace_drawers]
    GetCollection --> BatchLoop{More Batches?}
    
    BatchLoop -->|Yes| GetBatch[Get Batch<br/>from ChromaDB]
    GetBatch --> ProcessItems[Process Each Item]
    
    ProcessItems --> CalcHash[Calculate Content Hash]
    CalcHash --> CheckChange{Content Changed?}
    
    CheckChange -->|Yes| GenEmbed[Generate Embedding<br/>Optional]
    CheckChange -->|No| SkipItem[Skip Unchanged]
    SkipItem --> BatchLoop
    
    GenEmbed --> CheckLimit{Within Limit?}
    CheckLimit -->|Yes| QueueWrite[Queue for Write]
    CheckLimit -->|No| StopBatch[Stop Processing]
    
    QueueWrite --> BatchLoop
    StopBatch --> WritePhase
    BatchLoop -->|No| WritePhase[Write Phase]
    
    WritePhase --> CheckWorkers{Parallel<br/>Workers > 1?}
    CheckWorkers -->|Yes| ParallelWrite[Parallel Write<br/>ThreadPoolExecutor]
    CheckWorkers -->|No| SequentialWrite[Sequential Write]
    
    ParallelWrite --> PostAPI[POST /memory/write]
    SequentialWrite --> PostAPI
    
    PostAPI --> CheckResult{Success?}
    CheckResult -->|Yes| RecordSuccess[Record Success<br/>Update State]
    CheckResult -->|No| RecordFail[Record Failure]
    
    RecordSuccess --> MoreWrites{More Writes?}
    RecordFail --> MoreWrites
    MoreWrites -->|Yes| WritePhase
    MoreWrites -->|No| SaveState[Save sync-state.json]
    
    SaveState --> SaveHistory[Append sync-history.jsonl]
    SaveHistory --> ReturnSummary[Return Summary JSON]
    ReturnSummary --> End([End])
    
    style Start fill:#e1f5fe
    style End fill:#e1f5fe
    style LoadConfig fill:#fff9c4
    style LoadState fill:#fff9c4
    style SaveState fill:#fff9c4
    style SaveHistory fill:#fff9c4
    style PostAPI fill:#f3e5f5
```

### Sync State Management

```mermaid
graph LR
    subgraph StateFiles["State Files"]
        A[sync-state.json]
        B[sync-history.jsonl]
        C[bridge.config.json]
    end
    
    subgraph StateContents["State Contents"]
        D["version: 1"]
        E["synced: {drawer_id -> {hash, embedding, lastSync}}"]
        F["lastRunUtc: ISO timestamp"]
        G["lastSummary: {stats}"]
    end
    
    subgraph HistoryContents["History Contents"]
        H["timestamp"]
        I["seen, writes, failed, skipped"]
        J["mode, workers"]
    end
    
    subgraph ConfigContents["Config Contents"]
        K["orchestratorUrl"]
        L["palacePath"]
        M["collectionName"]
        N["defaultProjectName"]
        O["topicPrefix"]
        P["wingProjectMap"]
    end
    
    A --> D
    A --> E
    A --> F
    A --> G
    
    B --> H
    B --> I
    B --> J
    
    C --> K
    C --> L
    C --> M
    C --> N
    C --> O
    C --> P
    
    style StateFiles fill:#e3f2fd
    style StateContents fill:#e8f5e9
    style HistoryContents fill:#fff3e0
    style ConfigContents fill:#fce4ec
```

---

## Component Details

### PowerShell Module Structure

```mermaid
graph TB
    subgraph Module["LLMWorkflow Module"]
        direction TB
        
        subgraph PublicFunctions["Public Functions"]
            A1[Invoke-LLMWorkflowUp]
            A2[Install-LLMWorkflow]
            A3[Uninstall-LLMWorkflow]
            A4[Update-LLMWorkflow]
            A5[Test-LLMWorkflowSetup]
            A6[Get-LLMWorkflowVersion]
        end
        
        subgraph ProviderFunctions["Provider Functions"]
            B1[Get-ProviderProfile]
            B2[Resolve-ProviderProfile]
            B3[Get-ProviderPreferenceOrder]
            B4[Test-ProviderKey]
        end
        
        subgraph PrivateHelpers["Private Helpers"]
            C1[Get-UserModuleBasePath]
            C2[Get-EnvFileMap]
            C3[Remove-ProfileMarkerBlock]
        end
        
        subgraph Aliases["Aliases"]
            D1[llmup -> Invoke-LLMWorkflowUp]
            D2[llmdown -> Uninstall-LLMWorkflow]
            D3[llmcheck -> Test-LLMWorkflowSetup]
            D4[llmver -> Get-LLMWorkflowVersion]
            D5[llmupdate -> Update-LLMWorkflow]
        end
    end
    
    subgraph Manifest["Module Manifest"]
        E1[LLMWorkflow.psd1]
    end
    
    subgraph Scripts["Script Templates"]
        F1[bootstrap-llm-workflow.ps1]
        F2[install-global-llm-workflow.ps1]
    end
    
    subgraph ToolTemplates["Tool Templates"]
        G1[codemunch/]
        G2[contextlattice/]
        G3[memorybridge/]
    end
    
    PublicFunctions --> Module
    ProviderFunctions --> Module
    PrivateHelpers --> Module
    Aliases --> Module
    Manifest --> Module
    Scripts --> Module
    ToolTemplates --> Module
    
    style Module fill:#e3f2fd
    style PublicFunctions fill:#e8f5e9
    style ProviderFunctions fill:#fff3e0
    style PrivateHelpers fill:#fce4ec
    style Aliases fill:#f3e5f5
    style Manifest fill:#fff9c4
    style Scripts fill:#e0f2f1
    style ToolTemplates fill:#e0f2f1
```

### Python Bridge Components

```mermaid
graph TB
    subgraph PythonBridge["Python Bridge<br/>sync_mempalace_to_contextlattice.py"]
        direction TB
        
        subgraph Core["Core Functions"]
            A1[main]
            A2[_resolve]
            A3[_load_json]
            A4[_save_json]
        end
        
        subgraph ChromaDB["ChromaDB Integration"]
            B1[chromadb.PersistentClient]
            B2[collection.get]
            B3[_get_embedding_function]
        end
        
        subgraph HTTP["HTTP Operations"]
            C1[_post_json_with_retry]
            C2[_get_json_with_retry]
            C3[_is_retryable_error]
        end
        
        subgraph Processing["Content Processing"]
            D1[_is_content_changed]
            D2[cosine_similarity]
            D3[_generate_embedding]
            D4[_slug / _as_text]
        end
        
        subgraph Concurrency["Concurrency"]
            E1[SyncStateManager]
            E2[_write_single_drawer]
            E3[_process_writes_parallel]
            E4[ThreadPoolExecutor]
        end
        
        subgraph StateMgmt["State Management"]
            F1[_append_history]
            F2[record_success]
            F3[record_failure]
        end
    end
    
    Core --> Processing
    Core --> ChromaDB
    Core --> HTTP
    Core --> Concurrency
    Core --> StateMgmt
    Concurrency --> HTTP
    Processing --> ChromaDB
    
    style PythonBridge fill:#e3f2fd
    style Core fill:#e8f5e9
    style ChromaDB fill:#fff3e0
    style HTTP fill:#fce4ec
    style Processing fill:#f3e5f5
    style Concurrency fill:#e0f2f1
    style StateMgmt fill:#fff9c4
```

---

## Configuration File Hierarchy

```mermaid
graph TD
    subgraph ConfigHierarchy["Configuration Sources<br/>Priority: Top to Bottom"]
        A[CLI Arguments<br/>Highest Priority]
        B[Environment Variables]
        C[Config Files]
        D[Default Values<br/>Lowest Priority]
    end
    
    subgraph CLIArgs["CLI Arguments"]
        A1[--orchestrator-url]
        A2[--api-key]
        A3[--palace-path]
        A4[--collection-name]
        A5[--workers]
    end
    
    subgraph EnvVars["Environment Variables"]
        B1[CONTEXTLATTICE_ORCHESTRATOR_URL]
        B2[CONTEXTLATTICE_ORCHESTRATOR_API_KEY]
        B3[MEMPALACE_PALACE_PATH]
        B4[LLM_PROVIDER]
    end
    
    subgraph ConfigFiles["Config Files"]
        C1[.memorybridge/bridge.config.json]
        C2[.contextlattice/orchestrator.env]
        C3[.env]
    end
    
    subgraph Defaults["Default Values"]
        D1[http://127.0.0.1:8075]
        D2[~/.mempalace/palace]
        D3[mempalace_drawers]
        D4[4 workers]
    end
    
    A --> CLIArgs
    B --> EnvVars
    C --> ConfigFiles
    D --> Defaults
    
    style ConfigHierarchy fill:#e3f2fd
    style CLIArgs fill:#e8f5e9
    style EnvVars fill:#fff3e0
    style ConfigFiles fill:#fce4ec
    style Defaults fill:#f3e5f5
```

---

## Error Handling and Retry Logic

```mermaid
flowchart TD
    Start[HTTP Request] --> TryExecute[Execute Request]
    TryExecute --> CheckError{Error?}
    
    CheckError -->|No| Success[Return Response]
    CheckError -->|Yes| CheckRetryable{Is Retryable?}
    
    CheckRetryable -->|No| ThrowError[Throw Error]
    CheckRetryable -->|Yes| CheckMaxRetries{Max Retries<br/>Reached?}
    
    CheckMaxRetries -->|Yes| ThrowError
    CheckMaxRetries -->|No| CalculateDelay[Calculate Delay<br/>exponential backoff]
    
    CalculateDelay --> Sleep[Sleep]
    Sleep --> TryExecute
    
    subgraph RetryableErrors["Retryable Errors"]
        R1[HTTP 408 Timeout]
        R2[HTTP 429 Too Many Requests]
        R3[HTTP 500 Internal Error]
        R4[HTTP 502 Bad Gateway]
        R5[HTTP 503 Service Unavailable]
        R6[HTTP 504 Gateway Timeout]
        R7[Connection Refused]
        R8[Connection Reset]
        R9[Timeout]
    end
    
    subgraph NonRetryable["Non-Retryable Errors"]
        N1[HTTP 400 Bad Request]
        N2[HTTP 401 Unauthorized]
        N3[HTTP 403 Forbidden]
        N4[HTTP 404 Not Found]
    end
    
    style Start fill:#e1f5fe
    style Success fill:#e8f5e9
    style ThrowError fill:#ffebee
    style RetryableErrors fill:#fff3e0
    style NonRetryable fill:#fce4ec
```
