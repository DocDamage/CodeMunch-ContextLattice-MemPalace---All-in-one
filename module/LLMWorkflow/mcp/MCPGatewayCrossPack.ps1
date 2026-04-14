#requires -Version 5.1
Set-StrictMode -Version Latest

#>
function Invoke-MCPCrossPackQuery {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter()]
        [string[]]$TargetPacks = @(),

        [Parameter()]
        [string]$SessionId = '',

        [Parameter()]
        [bool]$AggregateResults = $true,

        [Parameter()]
        [int]$MaxResultsPerPack = 10,

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        Ensure-GatewayRunning
        if ([string]::IsNullOrEmpty($CorrelationId)) {
            $CorrelationId = [Guid]::NewGuid().ToString()
        }
        $queryId = [Guid]::NewGuid().ToString()
        $startTime = [DateTime]::UtcNow
    }

    process {
        # Determine target packs if not specified
        if ($TargetPacks.Count -eq 0) {
            $TargetPacks = Get-CrossPackTargets -Query $Query
        }

        if ($TargetPacks.Count -eq 0) {
            return [PSCustomObject]@{
                success = $false
                queryId = $queryId
                query = $Query
                error = "No target packs available for query"
                results = @()
                correlationId = $CorrelationId
            }
        }

        # Execute query on each target pack
        $packResults = @()
        foreach ($packId in $TargetPacks) {
            $route = $script:GatewayState.routes[$packId]
            if (-not $route -or -not $route.enabled) {
                continue
            }

            # Check circuit breaker
            if ($script:GatewayState.config.enableCircuitBreaker) {
                $cbResult = Test-CircuitBreaker -PackId $packId
                if (-not $cbResult.allowed) {
                    $packResults += [PSCustomObject]@{
                        packId = $packId
                        success = $false
                        error = "Circuit breaker open"
                        results = @()
                        resultCount = 0
                    }
                    continue
                }
            }

            try {
                $toolName = "$($route.prefix)query"
                $arguments = @{
                    query = $Query
                    maxResults = $MaxResultsPerPack
                }

                $result = Invoke-ToolAtEndpoint -Route $route -ToolName $toolName -Arguments $arguments -SessionId $SessionId -CorrelationId $CorrelationId
                
                Record-CircuitBreakerSuccess -PackId $packId
                
                $packResults += [PSCustomObject]@{
                    packId = $packId
                    success = $true
                    results = $result
                    resultCount = if ($result -is [array]) { $result.Count } else { 1 }
                }
            }
            catch {
                Record-CircuitBreakerFailure -PackId $packId
                
                $packResults += [PSCustomObject]@{
                    packId = $packId
                    success = $false
                    error = $_.Exception.Message
                    results = @()
                    resultCount = 0
                }
            }
        }

        $duration = ([DateTime]::UtcNow - $startTime).TotalMilliseconds

        # Log cross-pack query
        Write-GatewayStructuredLog -Level INFO -Message "Cross-pack query executed" -CorrelationId $CorrelationId -Metadata @{
            queryId = $queryId
            query = $Query
            targetPacks = $TargetPacks
            successfulPacks = ($packResults | Where-Object { $_.success } | Measure-Object).Count
            durationMs = [Math]::Round($duration, 2)
        }

        # Aggregate or return raw results
        if ($AggregateResults) {
            return [PSCustomObject]@{
                success = ($packResults | Where-Object { $_.success } | Measure-Object).Count -gt 0
                queryId = $queryId
                correlationId = $CorrelationId
                query = $Query
                targetPacks = $TargetPacks
                packResults = $packResults
                totalResults = ($packResults | Measure-Object -Property resultCount -Sum).Sum
                durationMs = [Math]::Round($duration, 2)
                aggregatedAt = [DateTime]::UtcNow.ToString("o")
            }
        }

        return $packResults
    }
}


#>
function Invoke-MCPAggregatedTool {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter()]
        [hashtable]$Arguments = @{},

        [Parameter()]
        [string]$SessionId = '',

        [Parameter()]
        [switch]$UseFallback,

        [Parameter()]
        [int]$TimeoutSeconds = 60,

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        Ensure-GatewayRunning
        if ([string]::IsNullOrEmpty($CorrelationId)) {
            $CorrelationId = [Guid]::NewGuid().ToString()
        }
    }

    process {
        # Route the request
        $routeResult = Invoke-MCPGatewayRequest -ToolName $ToolName -Arguments $Arguments -SessionId $SessionId -CorrelationId $CorrelationId

        if (-not $routeResult.result) {
            # Try fallback if enabled and primary failed
            if ($UseFallback) {
                $primaryPack = Resolve-PackFromToolName -ToolName $ToolName
                $fallbackPack = Get-FallbackPack -PackId $primaryPack

                if ($fallbackPack -and $fallbackPack -ne $primaryPack) {
                    Write-Verbose "Attempting fallback to pack: $fallbackPack"
                    $fallbackRoute = $script:GatewayState.routes[$fallbackPack]

                    if ($fallbackRoute -and $fallbackRoute.enabled) {
                        try {
                            $fallbackResult = Invoke-ToolAtEndpoint -Route $fallbackRoute -ToolName $ToolName -Arguments $Arguments -SessionId $SessionId -CorrelationId $CorrelationId
                            
                            return [PSCustomObject]@{
                                success = $true
                                toolName = $ToolName
                                primaryPack = $primaryPack
                                fallbackPack = $fallbackPack
                                usedFallback = $true
                                response = $fallbackResult
                                correlationId = $CorrelationId
                            }
                        }
                        catch {
                            Write-Warning "Fallback execution failed: $($_.Exception.Message)"
                        }
                    }
                }
            }
        }

        return $routeResult
    }
}


#>
function Get-MCPCrossPackEvidence {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Claim,

        [Parameter()]
        [string[]]$SourcePacks = @(),

        [Parameter()]
        [double]$MinConfidence = 0.5,

        [Parameter()]
        [string]$SessionId = '',

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        Ensure-GatewayRunning
        if ([string]::IsNullOrEmpty($CorrelationId)) {
            $CorrelationId = [Guid]::NewGuid().ToString()
        }
        $queryId = [Guid]::NewGuid().ToString()
    }

    process {
        # Use all enabled packs if none specified
        if ($SourcePacks.Count -eq 0) {
            $SourcePacks = $script:GatewayState.routes.Values |
                Where-Object { $_.enabled } |
                Select-Object -ExpandProperty packId
        }

        $evidenceList = @()
        foreach ($packId in $SourcePacks) {
            $route = $script:GatewayState.routes[$packId]
            if (-not $route -or -not $route.enabled) {
                continue
            }

            try {
                $toolName = "$($route.prefix)get_evidence"
                $arguments = @{
                    claim = $Claim
                    minConfidence = $MinConfidence
                }

                $result = Invoke-ToolAtEndpoint -Route $route -ToolName $toolName -Arguments $arguments -SessionId $SessionId -CorrelationId $CorrelationId

                $evidenceList += [PSCustomObject]@{
                    packId = $packId
                    claim = $Claim
                    evidence = $result
                    confidence = if ($result.confidence) { $result.confidence } else { 0.5 }
                    hasEvidence = $null -ne $result -and ($result -isnot [array] -or $result.Count -gt 0)
                }
            }
            catch {
                $evidenceList += [PSCustomObject]@{
                    packId = $packId
                    claim = $Claim
                    evidence = $null
                    confidence = 0
                    hasEvidence = $false
                    error = $_.Exception.Message
                }
            }
        }

        # Calculate aggregate confidence
        $confidentEvidence = $evidenceList | Where-Object { $_.confidence -ge $MinConfidence }
        $aggregateConfidence = if ($evidenceList.Count -gt 0) {
            ($evidenceList | Measure-Object -Property confidence -Average).Average
        }
        else {
            0
        }

        return [PSCustomObject]@{
            queryId = $queryId
            correlationId = $CorrelationId
            claim = $Claim
            evidenceList = $evidenceList
            supportingPacks = ($confidentEvidence | Where-Object { $_.hasEvidence } | Select-Object -ExpandProperty packId)
            aggregateConfidence = [Math]::Round($aggregateConfidence, 3)
            totalSources = $evidenceList.Count
            supportingSourceCount = ($confidentEvidence | Where-Object { $_.hasEvidence } | Measure-Object).Count
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
}


#>
function New-MCPCrossPackContext {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$PackIds,

        [Parameter()]
        [hashtable]$InitialData = @{},

        [Parameter()]
        [string]$SessionId = '',

        [Parameter()]
        [int]$ExpiryMinutes = 30,

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        Ensure-GatewayRunning
        if ([string]::IsNullOrEmpty($CorrelationId)) {
            $CorrelationId = [Guid]::NewGuid().ToString()
        }
    }

    process {
        # Create or extend session
        if ([string]::IsNullOrEmpty($SessionId)) {
            $session = New-MCPSession -ContextData $InitialData -ExpiryMinutes $ExpiryMinutes
        }
        else {
            $session = Get-MCPSession -SessionId $SessionId
            if (-not $session) {
                throw "Session '$SessionId' not found"
            }
        }

        $contextId = [Guid]::NewGuid().ToString()
        $validPackIds = @()

        # Initialize pack contexts
        foreach ($packId in $PackIds) {
            $route = $script:GatewayState.routes[$packId]
            if (-not $route -or -not $route.enabled) {
                Write-Warning "Pack '$packId' not available for cross-pack context"
                continue
            }

            try {
                $toolName = "$($route.prefix)init_context"
                $arguments = @{
                    contextId = $contextId
                    initialData = $InitialData
                }

                Invoke-ToolAtEndpoint -Route $route -ToolName $toolName -Arguments $arguments -SessionId $session.sessionId -CorrelationId $CorrelationId | Out-Null

                $session.packContexts[$packId] = @{
                    joinedAt = [DateTime]::UtcNow.ToString("o")
                    contextId = $contextId
                }
                $validPackIds += $packId
            }
            catch {
                Write-Warning "Failed to initialize context in pack '$packId': $($_.Exception.Message)"
            }
        }

        # Update session
        $script:GatewayState.sessions[$session.sessionId] = $session

        return [PSCustomObject]@{
            contextId = $contextId
            correlationId = $CorrelationId
            sessionId = $session.sessionId
            packIds = $validPackIds
            createdAt = [DateTime]::UtcNow.ToString("o")
            expiresAt = $session.expiresAt
            sharedData = $InitialData
        }
    }
}


#>
function Invoke-MCPBlenderToGodotExport {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [hashtable]$Options = @{},

        [Parameter()]
        [string]$SessionId = '',

        [Parameter()]
        [switch]$WaitForCompletion,

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        Ensure-GatewayRunning
        if ([string]::IsNullOrEmpty($CorrelationId)) {
            $CorrelationId = [Guid]::NewGuid().ToString()
        }
        $operationId = [Guid]::NewGuid().ToString()
        $startTime = [DateTime]::UtcNow
    }

    process {
        # Verify Blender pack is available
        $blenderRoute = $script:GatewayState.routes['blender-engine']
        if (-not $blenderRoute -or -not $blenderRoute.enabled) {
            return [PSCustomObject]@{
                success = $false
                operationId = $operationId
                correlationId = $CorrelationId
                error = "Blender pack not available"
                errorCode = 'PACK_UNAVAILABLE'
            }
        }

        # Verify Godot pack is available
        $godotRoute = $script:GatewayState.routes['godot-engine']
        if (-not $godotRoute -or -not $godotRoute.enabled) {
            return [PSCustomObject]@{
                success = $false
                operationId = $operationId
                correlationId = $CorrelationId
                error = "Godot pack not available"
                errorCode = 'PACK_UNAVAILABLE'
            }
        }

        # Initialize pipeline step
        $pipelineId = "blender-to-godot-$operationId"
        $stepConfig = @{
            stepId = 'blender-export'
            toolName = 'blender_export_godot'
            arguments = @{
                sourcePath = $SourcePath
                outputPath = $OutputPath
                format = if ($Options.format) { $Options.format } else { 'glTF2' }
                options = $Options
            }
        }
        Register-MCPPipelineStep -PipelineId $pipelineId -StepConfig $stepConfig | Out-Null

        # Execute Blender export
        try {
            $exportResult = Invoke-ToolAtEndpoint `
                -Route $blenderRoute `
                -ToolName $stepConfig.toolName `
                -Arguments $stepConfig.arguments `
                -SessionId $SessionId `
                -CorrelationId $CorrelationId

            # Update pipeline status
            $script:GatewayState.pipelines[$pipelineId].status = 'completed'
            $script:GatewayState.pipelines[$pipelineId].completedAt = [DateTime]::UtcNow.ToString("o")
            $script:GatewayState.pipelines[$pipelineId].result = $exportResult

            $duration = ([DateTime]::UtcNow - $startTime).TotalSeconds

            Write-GatewayStructuredLog -Level INFO -Message "Blender to Godot export completed" -CorrelationId $CorrelationId -Metadata @{
                operationId = $operationId
                pipelineId = $pipelineId
                sourcePath = $SourcePath
                outputPath = $OutputPath
                durationSeconds = [Math]::Round($duration, 2)
            }

            return [PSCustomObject]@{
                success = $true
                operationId = $operationId
                correlationId = $CorrelationId
                pipelineId = $pipelineId
                sourcePath = $SourcePath
                outputPath = $OutputPath
                result = $exportResult
                durationSeconds = [Math]::Round($duration, 2)
                completedAt = [DateTime]::UtcNow.ToString("o")
            }
        }
        catch {
            $script:GatewayState.pipelines[$pipelineId].status = 'failed'
            $script:GatewayState.pipelines[$pipelineId].error = $_.Exception.Message

            return [PSCustomObject]@{
                success = $false
                operationId = $operationId
                correlationId = $CorrelationId
                pipelineId = $pipelineId
                error = $_.Exception.Message
                errorCode = 'EXPORT_FAILED'
            }
        }
    }
}


#>
function Get-MCPPipelineStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PipelineId,

        [Parameter()]
        [switch]$IncludeHistory
    )

    begin {
        Ensure-GatewayRunning
    }

    process {
        if (-not $script:GatewayState.pipelines.ContainsKey($PipelineId)) {
            return [PSCustomObject]@{
                found = $false
                pipelineId = $PipelineId
                error = "Pipeline not found"
            }
        }

        $pipeline = $script:GatewayState.pipelines[$PipelineId]

        $result = [PSCustomObject]@{
            found = $true
            pipelineId = $PipelineId
            status = $pipeline.status
            createdAt = $pipeline.createdAt
            startedAt = $pipeline.startedAt
            completedAt = $pipeline.completedAt
            steps = ($pipeline.steps | Measure-Object).Count
            currentStep = $pipeline.currentStep
        }

        if ($IncludeHistory) {
            $result | Add-Member -NotePropertyName 'stepHistory' -NotePropertyValue $pipeline.steps -Force
            $result | Add-Member -NotePropertyName 'logs' -NotePropertyValue $pipeline.logs -Force
        }

        if ($pipeline.status -eq 'failed' -and $pipeline.error) {
            $result | Add-Member -NotePropertyName 'error' -NotePropertyValue $pipeline.error -Force
        }

        if ($pipeline.status -eq 'completed' -and $pipeline.result) {
            $result | Add-Member -NotePropertyName 'result' -NotePropertyValue $pipeline.result -Force
        }

        return $result
    }
}


#>
function Register-MCPPipelineStep {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PipelineId,

        [Parameter(Mandatory = $true)]
        [hashtable]$StepConfig,

        [Parameter()]
        [string[]]$DependsOn = @()
    )

    begin {
        Ensure-GatewayRunning
    }

    process {
        # Create pipeline if it doesn't exist
        if (-not $script:GatewayState.pipelines.ContainsKey($PipelineId)) {
            $script:GatewayState.pipelines[$PipelineId] = @{
                pipelineId = $PipelineId
                status = 'pending'
                createdAt = [DateTime]::UtcNow.ToString("o")
                startedAt = $null
                completedAt = $null
                steps = @()
                currentStep = $null
                stepIndex = @{}
                logs = @()
                result = $null
                error = $null
            }
        }

        $pipeline = $script:GatewayState.pipelines[$PipelineId]

        # Validate step configuration
        if (-not $StepConfig.stepId) {
            throw "Step configuration must include 'stepId'"
        }
        if (-not $StepConfig.toolName) {
            throw "Step configuration must include 'toolName'"
        }

        # Check for duplicate step ID
        if ($pipeline.stepIndex.ContainsKey($StepConfig.stepId)) {
            throw "Step '$($StepConfig.stepId)' already exists in pipeline '$PipelineId'"
        }

        $step = [PSCustomObject]@{
            stepId = $StepConfig.stepId
            toolName = $StepConfig.toolName
            arguments = if ($StepConfig.arguments) { $StepConfig.arguments } else { @{} }
            dependsOn = $DependsOn
            status = 'pending'
            registeredAt = [DateTime]::UtcNow.ToString("o")
            startedAt = $null
            completedAt = $null
            result = $null
            error = $null
        }

        $pipeline.steps += $step
        $pipeline.stepIndex[$StepConfig.stepId] = $pipeline.steps.Count - 1

        Add-GatewayLog -Level 'Info' -Message "Pipeline step registered" -Context @{
            pipelineId = $PipelineId
            stepId = $StepConfig.stepId
            toolName = $StepConfig.toolName
        }

        return [PSCustomObject]@{
            pipelineId = $PipelineId
            stepId = $StepConfig.stepId
            status = 'registered'
            stepIndex = $pipeline.steps.Count - 1
        }
    }
}


