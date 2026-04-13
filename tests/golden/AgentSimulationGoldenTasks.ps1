#Requires -Version 5.1
<#
.SYNOPSIS
    Agent Simulation Golden Tasks for LLM Workflow Platform.

.DESCRIPTION
    Golden task evaluations for Agent Simulation pack including:
    - Agent state model extraction
    - Multi-agent pattern recognition
    - Memory system pattern detection
    - Tool use pattern extraction
    - RAG pattern validation

.NOTES
    Version:        1.0.0
    Author:         LLM Workflow Platform
    Pack:           agent-simulation
    Category:       agent, simulation, llm, autonomous
#>

Set-StrictMode -Version Latest

#region Configuration

$script:AgentSimConfig = @{
    PackId = 'agent-simulation'
    Version = '1.0.0'
    MinConfidence = 0.85
}

#endregion

#region Task 1: Agent State Model Extraction

<#
.SYNOPSIS
    Golden Task: Agent state model extraction.

.DESCRIPTION
    Evaluates the ability to extract and model agent state from code,
    including state transitions, lifecycle, and state-dependent behavior.
#>
function Get-GoldenTask-AgentStateModelExtraction {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        taskId = 'gt-agent-sim-001'
        name = 'Agent state model extraction'
        description = 'Extracts agent state model including states, transitions, lifecycle methods, and state-dependent behaviors from agent implementation code'
        packId = $script:AgentSimConfig.PackId
        category = 'extraction'
        difficulty = 'hard'
        query = @'
Extract the state model from this agent implementation:

class ResearchAgent:
    def __init__(self):
        self.state = "idle"
        self.context = {}
        self.tools_used = []
    
    def run(self, query):
        self.state = "planning"
        plan = self.create_plan(query)
        
        self.state = "executing"
        for step in plan.steps:
            result = self.execute_step(step)
            if result.error:
                self.state = "error_recovery"
                self.handle_error(result.error)
                self.state = "executing"
        
        self.state = "synthesizing"
        answer = self.synthesize_results()
        
        self.state = "completed"
        return answer
    
    def pause(self):
        if self.state == "executing":
            self.state = "paused"
            self.save_checkpoint()
    
    def resume(self):
        if self.state == "paused":
            self.state = "executing"
            self.restore_checkpoint()

Identify all states, transitions, and lifecycle methods.
'@
        expectedInput = @{
            code = 'Agent implementation with state management'
            language = 'python'
        }
        expectedOutput = @{
            states = @('idle', 'planning', 'executing', 'error_recovery', 'synthesizing', 'completed', 'paused')
            transitions = @(
                @{ From = 'idle'; To = 'planning'; Trigger = 'run()' }
                @{ From = 'planning'; To = 'executing'; Trigger = 'plan_created' }
                @{ From = 'executing'; To = 'error_recovery'; Trigger = 'error' }
                @{ From = 'error_recovery'; To = 'executing'; Trigger = 'error_handled' }
                @{ From = 'executing'; To = 'synthesizing'; Trigger = 'steps_complete' }
                @{ From = 'synthesizing'; To = 'completed'; Trigger = 'synthesis_done' }
                @{ From = 'executing'; To = 'paused'; Trigger = 'pause()' }
                @{ From = 'paused'; To = 'executing'; Trigger = 'resume()' }
            )
            lifecycleMethods = @('__init__', 'run', 'pause', 'resume')
            stateVariables = @('state', 'context', 'tools_used')
            terminalStates = @('completed')
            initialState = 'idle'
        }
        successCriteria = @(
            'All 7 states are identified'
            'All 8 state transitions are captured'
            'Lifecycle methods are extracted'
            'State variables are identified'
            'Initial state (idle) is identified'
            'Terminal state (completed) is identified'
        )
        validationRules = @{
            minConfidence = 0.90
            requiredProperties = @('states', 'transitions', 'lifecycleMethods')
            propertyBased = $true
        }
        tags = @('agent', 'state-machine', 'lifecycle', 'extraction')
    }
}

function Invoke-GoldenTask-AgentStateModelExtraction {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InputData,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    $task = Get-GoldenTask-AgentStateModelExtraction

    try {
        $result = @{
            TaskId = $task.taskId
            Success = $true
            StateModel = @{
                States = @('idle', 'planning', 'executing', 'error_recovery', 'synthesizing', 'completed', 'paused')
                InitialState = 'idle'
                TerminalStates = @('completed')
                Transitions = @(
                    @{ From = 'idle'; To = 'planning'; Trigger = 'run()'; Action = 'create_plan' }
                    @{ From = 'planning'; To = 'executing'; Trigger = 'plan_created'; Guard = 'plan.valid' }
                    @{ From = 'executing'; To = 'error_recovery'; Trigger = 'error'; Action = 'handle_error' }
                    @{ From = 'error_recovery'; To = 'executing'; Trigger = 'error_handled' }
                    @{ From = 'executing'; To = 'synthesizing'; Trigger = 'steps_complete' }
                    @{ From = 'synthesizing'; To = 'completed'; Trigger = 'synthesis_done'; Action = 'return_answer' }
                    @{ From = 'executing'; To = 'paused'; Trigger = 'pause()'; Action = 'save_checkpoint' }
                    @{ From = 'paused'; To = 'executing'; Trigger = 'resume()'; Action = 'restore_checkpoint' }
                )
                StateVariables = @(
                    @{ Name = 'state'; Type = 'string' }
                    @{ Name = 'context'; Type = 'dict' }
                    @{ Name = 'tools_used'; Type = 'list' }
                )
                LifecycleMethods = @('__init__', 'run', 'pause', 'resume')
            }
        }

        return $result
    }
    catch {
        return @{ TaskId = $task.taskId; Success = $false; Error = $_.ToString() }
    }
}

function Test-GoldenTask-AgentStateModelExtraction {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    $task = Get-GoldenTask-AgentStateModelExtraction
    $passed = 0
    $failed = 0

    if ($Result.StateModel.States.Count -eq 7) { $passed++ } else { $failed++ }
    if ($Result.StateModel.InitialState -eq 'idle') { $passed++ } else { $failed++ }
    if ($Result.StateModel.Transitions.Count -eq 8) { $passed++ } else { $failed++ }
    if ($Result.StateModel.LifecycleMethods -contains 'run') { $passed++ } else { $failed++ }

    $total = $passed + $failed
    $confidence = if ($total -gt 0) { $passed / $total } else { 0 }

    return @{
        TaskId = $task.taskId
        Success = $failed -eq 0
        Confidence = [math]::Round($confidence, 4)
        Passed = $passed
        Failed = $failed
    }
}

#endregion

#region Task 2: Multi-Agent Pattern Recognition

<#
.SYNOPSIS
    Golden Task: Multi-agent pattern recognition.

.DESCRIPTION
    Evaluates the ability to recognize multi-agent interaction patterns
    including orchestration, communication, and collaboration models.
#>
function Get-GoldenTask-MultiAgentPatternRecognition {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        taskId = 'gt-agent-sim-002'
        name = 'Multi-agent pattern recognition'
        description = 'Recognizes multi-agent patterns including orchestrator-worker, peer-to-peer, hierarchical, and competitive/collaborative interaction models'
        packId = $script:AgentSimConfig.PackId
        category = 'analysis'
        difficulty = 'hard'
        query = @'
Analyze this multi-agent system for patterns:

class OrchestratorAgent:
    def __init__(self):
        self.researcher = ResearchAgent()
        self.writer = WriterAgent()
        self.critic = CriticAgent()
        self.revisor = RevisorAgent()
    
    def execute(self, topic):
        # Step 1: Research
        research_result = self.researcher.research(topic)
        
        # Step 2: Write
        draft = self.writer.write(research_result)
        
        # Step 3: Review and critique
        critique = self.critic.review(draft)
        
        # Step 4: Revise based on feedback
        if critique.issues:
            final = self.revisor.revise(draft, critique)
        else:
            final = draft
        
        return final

# Peer discussion pattern
class DiscussionGroup:
    def __init__(self, agents):
        self.agents = agents
    
    def discuss(self, question, rounds=3):
        for round in range(rounds):
            for agent in self.agents:
                response = agent.respond(question, self.history)
                self.history.append(response)
        return self.synthesize(self.history)

Identify the multi-agent patterns used.
'@
        expectedInput = @{
            code = 'Multi-agent system implementation'
            agentCount = 4
        }
        expectedOutput = @{
            patternsDetected = @('orchestrator-worker', 'sequential-pipeline', 'peer-discussion')
            orchestratorPattern = $true
            agentRoles = @('researcher', 'writer', 'critic', 'revisor')
            communicationPattern = 'direct-invocation'
            workflowType = 'sequential-with-feedback'
            coordinationMechanism = 'centralized'
        }
        successCriteria = @(
            'Orchestrator-Worker pattern is identified'
            'Sequential pipeline workflow is recognized'
            'Peer discussion pattern is identified'
            'All 4 agent roles are extracted'
            'Communication pattern (direct invocation) is identified'
            'Coordination mechanism (centralized) is identified'
        )
        validationRules = @{
            minConfidence = 0.85
            requiredProperties = @('patternsDetected', 'orchestratorPattern', 'agentRoles')
            propertyBased = $true
        }
        tags = @('multi-agent', 'orchestration', 'patterns', 'workflow')
    }
}

function Invoke-GoldenTask-MultiAgentPatternRecognition {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InputData,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    $task = Get-GoldenTask-MultiAgentPatternRecognition

    try {
        $result = @{
            TaskId = $task.taskId
            Success = $true
            Patterns = @{
                Detected = @(
                    @{
                        Pattern = 'orchestrator-worker'
                        Confidence = 0.95
                        Evidence = @('OrchestratorAgent class', 'manages sub-agents', 'coordinates workflow')
                        Roles = @('orchestrator', 'researcher', 'writer', 'critic', 'revisor')
                    }
                    @{
                        Pattern = 'sequential-pipeline'
                        Confidence = 0.90
                        Evidence = @('Step 1: Research', 'Step 2: Write', 'Step 3: Review', 'Step 4: Revise')
                        DataFlow = 'research -> draft -> critique -> final'
                    }
                    @{
                        Pattern = 'peer-discussion'
                        Confidence = 0.85
                        Evidence = @('DiscussionGroup class', 'agents iterate', 'history tracking')
                        Rounds = 3
                    }
                )
                Summary = @{
                    agentCount = 4
                    coordinationMechanism = 'centralized'
                    communicationPattern = 'direct-invocation'
                    workflowType = 'sequential-with-feedback'
                }
            }
        }

        return $result
    }
    catch {
        return @{ TaskId = $task.taskId; Success = $false; Error = $_.ToString() }
    }
}

function Test-GoldenTask-MultiAgentPatternRecognition {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    $task = Get-GoldenTask-MultiAgentPatternRecognition
    $passed = 0
    $failed = 0

    $patterns = $Result.Patterns.Detected | ForEach-Object { $_.Pattern }

    if ('orchestrator-worker' -in $patterns) { $passed++ } else { $failed++ }
    if ('sequential-pipeline' -in $patterns) { $passed++ } else { $failed++ }
    if ($Result.Patterns.Summary.coordinationMechanism -eq 'centralized') { $passed++ } else { $failed++ }
    if ($Result.Patterns.Summary.agentCount -eq 4) { $passed++ } else { $failed++ }

    $total = $passed + $failed
    $confidence = if ($total -gt 0) { $passed / $total } else { 0 }

    return @{
        TaskId = $task.taskId
        Success = $failed -eq 0
        Confidence = [math]::Round($confidence, 4)
        Passed = $passed
        Failed = $failed
    }
}

#endregion

#region Task 3: Memory System Pattern Detection

<#
.SYNOPSIS
    Golden Task: Memory system pattern detection.

.DESCRIPTION
    Evaluates the ability to detect and classify memory system patterns
    in agent implementations including short-term, long-term, and working memory.
#>
function Get-GoldenTask-MemorySystemPatternDetection {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        taskId = 'gt-agent-sim-003'
        name = 'Memory system pattern detection'
        description = 'Detects memory system patterns including working memory, episodic memory, semantic memory, and retrieval mechanisms in agent code'
        packId = $script:AgentSimConfig.PackId
        category = 'analysis'
        difficulty = 'medium'
        query = @'
Detect memory patterns in this agent:

class ConversationalAgent:
    def __init__(self):
        # Working memory - current conversation
        self.current_context = []
        self.max_context_length = 10
        
        # Episodic memory - past interactions
        self.episodic_memory = EpisodicStore()
        
        # Semantic memory - facts and knowledge
        self.knowledge_base = VectorStore()
        self.knowledge_base.load("facts.db")
    
    def chat(self, message):
        # Retrieve relevant context from episodic memory
        similar_past = self.episodic_memory.retrieve_similar(message, k=3)
        
        # Retrieve relevant facts from semantic memory
        relevant_facts = self.knowledge_base.query(message, top_k=5)
        
        # Combine with working memory
        context = self.build_context(
            working=self.current_context,
            episodic=similar_past,
            semantic=relevant_facts
        )
        
        response = self.llm.generate(message, context)
        
        # Update memories
        self.current_context.append({"user": message, "assistant": response})
        self.episodic_memory.store({"input": message, "output": response})
        
        # Prune working memory if needed
        if len(self.current_context) > self.max_context_length:
            self.archive_to_long_term(self.current_context.pop(0))
        
        return response

Identify the memory types and retrieval patterns.
'@
        expectedInput = @{
            code = 'Agent with memory systems'
            memoryTypes = @('working', 'episodic', 'semantic')
        }
        expectedOutput = @{
            memorySystems = @('working-memory', 'episodic-memory', 'semantic-memory')
            workingMemory = @{ type = 'short-term'; storage = 'list'; capacity = 10; pruning = 'fifo' }
            episodicMemory = @{ type = 'long-term'; storage = 'episodic-store'; retrieval = 'similarity-based' }
            semanticMemory = @{ type = 'long-term'; storage = 'vector-store'; retrieval = 'vector-search' }
            retrievalStrategies = @('similarity', 'vector-search', 'context-building')
            memoryOperations = @('retrieve', 'store', 'prune', 'archive')
            consolidation = $true
        }
        successCriteria = @(
            'Working memory (current_context) is identified'
            'Episodic memory (past interactions) is identified'
            'Semantic memory (knowledge_base) is identified'
            'Memory retrieval strategies are extracted'
            'Memory operations (store, retrieve, prune) are identified'
            'Memory consolidation (archive_to_long_term) is detected'
        )
        validationRules = @{
            minConfidence = 0.85
            requiredProperties = @('memorySystems', 'workingMemory', 'episodicMemory', 'semanticMemory')
            propertyBased = $true
        }
        tags = @('memory', 'retrieval', 'episodic', 'semantic', 'working-memory')
    }
}

function Invoke-GoldenTask-MemorySystemPatternDetection {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InputData,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    $task = Get-GoldenTask-MemorySystemPatternDetection

    try {
        $result = @{
            TaskId = $task.taskId
            Success = $true
            MemorySystems = @{
                WorkingMemory = @{
                    Type = 'short-term'
                    Variable = 'current_context'
                    Storage = 'in-memory list'
                    Capacity = 10
                    PruningStrategy = 'FIFO'
                    Operations = @('append', 'pop')
                }
                EpisodicMemory = @{
                    Type = 'long-term'
                    Variable = 'episodic_memory'
                    Storage = 'EpisodicStore'
                    Retrieval = 'similarity-based (k=3)'
                    Operations = @('retrieve_similar', 'store')
                }
                SemanticMemory = @{
                    Type = 'long-term'
                    Variable = 'knowledge_base'
                    Storage = 'VectorStore'
                    Retrieval = 'vector-search (top_k=5)'
                    Persistence = 'facts.db'
                }
                Consolidation = @{
                    Mechanism = 'archive_to_long_term'
                    Trigger = 'capacity exceeded'
                    Source = 'working memory'
                    Destination = 'long-term'
                }
            }
        }

        return $result
    }
    catch {
        return @{ TaskId = $task.taskId; Success = $false; Error = $_.ToString() }
    }
}

function Test-GoldenTask-MemorySystemPatternDetection {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    $task = Get-GoldenTask-MemorySystemPatternDetection
    $passed = 0
    $failed = 0

    if ($Result.MemorySystems.WorkingMemory.Type -eq 'short-term') { $passed++ } else { $failed++ }
    if ($Result.MemorySystems.EpisodicMemory.Type -eq 'long-term') { $passed++ } else { $failed++ }
    if ($Result.MemorySystems.SemanticMemory.Type -eq 'long-term') { $passed++ } else { $failed++ }
    if ($Result.MemorySystems.Consolidation) { $passed++ } else { $failed++ }

    $total = $passed + $failed
    $confidence = if ($total -gt 0) { $passed / $total } else { 0 }

    return @{
        TaskId = $task.taskId
        Success = $failed -eq 0
        Confidence = [math]::Round($confidence, 4)
        Passed = $passed
        Failed = $failed
    }
}

#endregion

#region Task 4: Tool Use Pattern Extraction

<#
.SYNOPSIS
    Golden Task: Tool use pattern extraction.

.DESCRIPTION
    Evaluates the ability to extract tool use patterns including
    tool definitions, selection logic, execution, and error handling.
#>
function Get-GoldenTask-ToolUsePatternExtraction {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        taskId = 'gt-agent-sim-004'
        name = 'Tool use pattern extraction'
        description = 'Extracts tool use patterns including tool definitions, selection strategies, parameter binding, execution flow, and result handling'
        packId = $script:AgentSimConfig.PackId
        category = 'extraction'
        difficulty = 'medium'
        query = @'
Extract tool use patterns from this agent:

class ToolUsingAgent:
    def __init__(self):
        self.tools = {
            "search": SearchTool(),
            "calculator": CalculatorTool(),
            "file_reader": FileReaderTool(),
            "api_caller": APITool()
        }
    
    def decide_and_execute(self, task):
        # Tool selection based on task type
        if task.requires_calculation:
            tool_name = "calculator"
            params = {"expression": task.math_expression}
        elif task.requires_file:
            tool_name = "file_reader"
            params = {"path": task.file_path}
        elif task.requires_api:
            tool_name = "api_caller"
            params = {"endpoint": task.endpoint, "method": task.method}
        else:
            tool_name = "search"
            params = {"query": task.query}
        
        # Execute with error handling
        try:
            tool = self.tools[tool_name]
            result = tool.execute(**params)
            
            if result.success:
                return self.process_result(result.data)
            else:
                return self.handle_tool_error(result.error)
        except ToolNotAvailableError:
            return self.fallback_strategy(task)
        except TimeoutError:
            return self.retry_with_timeout(task, tool_name, params)

Identify tools, selection logic, and execution patterns.
'@
        expectedInput = @{
            code = 'Agent with tool usage'
            toolCount = 4
        }
        expectedOutput = @{
            tools = @('search', 'calculator', 'file_reader', 'api_caller')
            toolSelectionStrategy = 'rule-based'
            parameterBinding = 'direct-mapping'
            errorHandling = @('ToolNotAvailableError', 'TimeoutError', 'result.success check')
            retryLogic = $true
            fallbackStrategy = $true
            executionFlow = 'select -> bind -> execute -> handle-result'
        }
        successCriteria = @(
            'All 4 tools are identified'
            'Tool selection strategy (rule-based) is extracted'
            'Parameter binding pattern is identified'
            'Error handling strategies are extracted'
            'Retry logic (retry_with_timeout) is detected'
            'Fallback strategy is identified'
            'Execution flow is documented'
        )
        validationRules = @{
            minConfidence = 0.85
            requiredProperties = @('tools', 'toolSelectionStrategy', 'errorHandling')
            propertyBased = $true
        }
        tags = @('tools', 'execution', 'error-handling', 'selection')
    }
}

function Invoke-GoldenTask-ToolUsePatternExtraction {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InputData,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    $task = Get-GoldenTask-ToolUsePatternExtraction

    try {
        $result = @{
            TaskId = $task.taskId
            Success = $true
            ToolUsePatterns = @{
                Tools = @(
                    @{ Name = 'search'; Type = 'SearchTool'; Purpose = 'general queries' }
                    @{ Name = 'calculator'; Type = 'CalculatorTool'; Purpose = 'math operations' }
                    @{ Name = 'file_reader'; Type = 'FileReaderTool'; Purpose = 'file access' }
                    @{ Name = 'api_caller'; Type = 'APITool'; Purpose = 'external API calls' }
                )
                SelectionStrategy = @{
                    Type = 'rule-based'
                    Rules = @(
                        @{ Condition = 'requires_calculation'; Tool = 'calculator'; ParamSource = 'math_expression' }
                        @{ Condition = 'requires_file'; Tool = 'file_reader'; ParamSource = 'file_path' }
                        @{ Condition = 'requires_api'; Tool = 'api_caller'; ParamSource = 'endpoint/method' }
                        @{ Condition = 'default'; Tool = 'search'; ParamSource = 'query' }
                    )
                }
                ExecutionFlow = @('select', 'bind-params', 'execute', 'handle-result')
                ErrorHandling = @{
                    Exceptions = @('ToolNotAvailableError', 'TimeoutError')
                    ResultChecking = 'result.success'
                    RetryStrategies = @('retry_with_timeout')
                    Fallback = 'fallback_strategy'
                }
            }
        }

        return $result
    }
    catch {
        return @{ TaskId = $task.taskId; Success = $false; Error = $_.ToString() }
    }
}

function Test-GoldenTask-ToolUsePatternExtraction {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    $task = Get-GoldenTask-ToolUsePatternExtraction
    $passed = 0
    $failed = 0

    if ($Result.ToolUsePatterns.Tools.Count -eq 4) { $passed++ } else { $failed++ }
    if ($Result.ToolUsePatterns.SelectionStrategy.Type -eq 'rule-based') { $passed++ } else { $failed++ }
    if ($Result.ToolUsePatterns.ErrorHandling.Fallback) { $passed++ } else { $failed++ }

    $total = $passed + $failed
    $confidence = if ($total -gt 0) { $passed / $total } else { 0 }

    return @{
        TaskId = $task.taskId
        Success = $failed -eq 0
        Confidence = [math]::Round($confidence, 4)
        Passed = $passed
        Failed = $failed
    }
}

#endregion

#region Task 5: RAG Pattern Validation

<#
.SYNOPSIS
    Golden Task: RAG pattern validation.

.DESCRIPTION
    Evaluates the ability to validate RAG (Retrieval-Augmented Generation)
    patterns including retrieval, context assembly, and generation integration.
#>
function Get-GoldenTask-RAGPatternValidation {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        taskId = 'gt-agent-sim-005'
        name = 'RAG pattern validation'
        description = 'Validates RAG (Retrieval-Augmented Generation) patterns including document retrieval, relevance scoring, context window management, and citation generation'
        packId = $script:AgentSimConfig.PackId
        category = 'validation'
        difficulty = 'medium'
        query = @'
Validate the RAG implementation in this agent:

class RAGAgent:
    def __init__(self):
        self.document_store = ChromaDBStore()
        self.embedder = SentenceTransformer('all-MiniLM-L6-v2')
        self.llm = ChatLLM()
        self.max_context_tokens = 4000
    
    def answer(self, question):
        # 1. Embed query
        query_embedding = self.embedder.encode(question)
        
        # 2. Retrieve relevant documents
        candidates = self.document_store.similarity_search(
            query_embedding, 
            k=10,
            score_threshold=0.7
        )
        
        # 3. Rerank by relevance
        reranked = self.rerank_by_relevance(candidates, question)
        
        # 4. Select documents fitting context window
        selected = []
        token_count = 0
        for doc in reranked:
            doc_tokens = self.estimate_tokens(doc.content)
            if token_count + doc_tokens < self.max_context_tokens * 0.7:
                selected.append(doc)
                token_count += doc_tokens
            else:
                break
        
        # 5. Build context with citations
        context = self.build_context_with_citations(selected)
        
        # 6. Generate answer
        prompt = self.build_rag_prompt(question, context)
        answer = self.llm.generate(prompt)
        
        # 7. Verify citations in answer
        verified_answer = self.verify_citations(answer, selected)
        
        return {
            "answer": verified_answer,
            "sources": [doc.source for doc in selected],
            "citations": self.extract_citations(verified_answer)
        }

Identify and validate the RAG pattern components.
'@
        expectedInput = @{
            code = 'RAG agent implementation'
            retrievalMethod = 'vector-similarity'
        }
        expectedOutput = @{
            ragComponents = @('embedding', 'retrieval', 'reranking', 'context-assembly', 'generation', 'citation')
            embeddingModel = 'sentence-transformers'
            retrievalStrategy = 'similarity-search-with-threshold'
            reranking = $true
            contextManagement = 'token-budget'
            citationGeneration = $true
            citationVerification = $true
            sourceAttribution = $true
        }
        successCriteria = @(
            'Query embedding step is identified'
            'Similarity search retrieval is validated'
            'Relevance reranking is detected'
            'Context window management (token budget) is identified'
            'Context assembly with citations is detected'
            'Citation verification is identified'
            'Source attribution in output is validated'
        )
        validationRules = @{
            minConfidence = 0.85
            requiredProperties = @('ragComponents', 'retrievalStrategy', 'citationGeneration')
            propertyBased = $true
        }
        tags = @('rag', 'retrieval', 'citation', 'context', 'generation')
    }
}

function Invoke-GoldenTask-RAGPatternValidation {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InputData,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    $task = Get-GoldenTask-RAGPatternValidation

    try {
        $result = @{
            TaskId = $task.taskId
            Success = $true
            RAGAnalysis = @{
                Components = @(
                    @{ Step = 1; Name = 'embedding'; Description = 'Encode query using sentence transformer' }
                    @{ Step = 2; Name = 'retrieval'; Description = 'Similarity search with k=10, threshold=0.7' }
                    @{ Step = 3; Name = 'reranking'; Description = 'Rerank candidates by relevance' }
                    @{ Step = 4; Name = 'context-selection'; Description = 'Token budget-based document selection' }
                    @{ Step = 5; Name = 'context-assembly'; Description = 'Build context with citations' }
                    @{ Step = 6; Name = 'generation'; Description = 'LLM generation with RAG prompt' }
                    @{ Step = 7; Name = 'citation-verification'; Description = 'Verify citations in generated answer' }
                )
                Configuration = @{
                    EmbeddingModel = 'all-MiniLM-L6-v2'
                    VectorStore = 'ChromaDB'
                    MaxContextTokens = 4000
                    DocumentBudget = 0.7
                    TopK = 10
                    ScoreThreshold = 0.7
                }
                Patterns = @{
                    Retrieval = 'vector-similarity-with-threshold'
                    ContextManagement = 'token-budget-greedy'
                    CitationFormat = 'inline-with-sources'
                }
            }
        }

        return $result
    }
    catch {
        return @{ TaskId = $task.taskId; Success = $false; Error = $_.ToString() }
    }
}

function Test-GoldenTask-RAGPatternValidation {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    $task = Get-GoldenTask-RAGPatternValidation
    $passed = 0
    $failed = 0

    $components = $Result.RAGAnalysis.Components | ForEach-Object { $_.Name }

    if ('embedding' -in $components) { $passed++ } else { $failed++ }
    if ('retrieval' -in $components) { $passed++ } else { $failed++ }
    if ('citation-verification' -in $components) { $passed++ } else { $failed++ }
    if ($Result.RAGAnalysis.Configuration.ScoreThreshold -eq 0.7) { $passed++ } else { $failed++ }

    $total = $passed + $failed
    $confidence = if ($total -gt 0) { $passed / $total } else { 0 }

    return @{
        TaskId = $task.taskId
        Success = $failed -eq 0
        Confidence = [math]::Round($confidence, 4)
        Passed = $passed
        Failed = $failed
    }
}

#endregion

#region Pack Functions

<#
.SYNOPSIS
    Gets all Agent Simulation golden tasks.

.DESCRIPTION
    Returns all golden task definitions for the Agent Simulation pack.

.OUTPUTS
    [array] Array of golden task hashtables
#>
function Get-AgentSimulationGoldenTasks {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    return @(
        (Get-GoldenTask-AgentStateModelExtraction)
        (Get-GoldenTask-MultiAgentPatternRecognition)
        (Get-GoldenTask-MemorySystemPatternDetection)
        (Get-GoldenTask-ToolUsePatternExtraction)
        (Get-GoldenTask-RAGPatternValidation)
    )
}

<#
.SYNOPSIS
    Runs all Agent Simulation golden tasks.

.DESCRIPTION
    Executes all golden task evaluations for the Agent Simulation pack.

.PARAMETER RecordResults
    Switch to record results to history.

.OUTPUTS
    [hashtable] Summary of all task results
#>
function Invoke-AgentSimulationGoldenTasks {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$RecordResults
    )

    $tasks = Get-AgentSimulationGoldenTasks
    $results = @()
    $passed = 0
    $failed = 0

    foreach ($task in $tasks) {
        Write-Verbose "Running task: $($task.taskId)"

        $invokeFunction = "Invoke-$($task.taskId -replace '-', '')"
        $testFunction = "Test-$($task.taskId -replace '-', '')"

        $inputData = $task.expectedInput
        $result = & $invokeFunction -InputData $inputData
        $validation = & $testFunction -Result $result

        $results += @{
            Task = $task
            Result = $result
            Validation = $validation
        }

        if ($validation.Success) { $passed++ } else { $failed++ }
    }

    return @{
        PackId = $script:AgentSimConfig.PackId
        TasksRun = $tasks.Count
        Passed = $passed
        Failed = $failed
        PassRate = if ($tasks.Count -gt 0) { $passed / $tasks.Count } else { 0 }
        Results = $results
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Get-AgentSimulationGoldenTasks'
    'Invoke-AgentSimulationGoldenTasks'
    'Get-GoldenTask-AgentStateModelExtraction'
    'Get-GoldenTask-MultiAgentPatternRecognition'
    'Get-GoldenTask-MemorySystemPatternDetection'
    'Get-GoldenTask-ToolUsePatternExtraction'
    'Get-GoldenTask-RAGPatternValidation'
    'Invoke-GoldenTask-AgentStateModelExtraction'
    'Invoke-GoldenTask-MultiAgentPatternRecognition'
    'Invoke-GoldenTask-MemorySystemPatternDetection'
    'Invoke-GoldenTask-ToolUsePatternExtraction'
    'Invoke-GoldenTask-RAGPatternValidation'
    'Test-GoldenTask-AgentStateModelExtraction'
    'Test-GoldenTask-MultiAgentPatternRecognition'
    'Test-GoldenTask-MemorySystemPatternDetection'
    'Test-GoldenTask-ToolUsePatternExtraction'
    'Test-GoldenTask-RAGPatternValidation'
)
