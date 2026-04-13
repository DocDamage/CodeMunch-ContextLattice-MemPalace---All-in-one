#requires -Version 5.1
<#
.SYNOPSIS
    Telemetry module tests for the LLMWorkflow observability backbone.

.DESCRIPTION
    Pester v5 test suite for:
    - SpanFactory.ps1: span creation, lifecycle, attributes, and events
    - TraceEnvelope.ps1: envelope creation, event addition, and closure
    - OpenTelemetryBridge.ps1: trace context initialization and payload helpers

.NOTES
    File: Telemetry.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+
#>

BeforeAll {
    $script:ModuleRoot = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "module") "LLMWorkflow") "telemetry"
    $script:TelemetryPath = $script:ModuleRoot

    $spanFactoryPath = Join-Path $script:TelemetryPath "SpanFactory.ps1"
    $traceEnvelopePath = Join-Path $script:TelemetryPath "TraceEnvelope.ps1"
    $otelBridgePath = Join-Path $script:TelemetryPath "OpenTelemetryBridge.ps1"

    if (Test-Path $spanFactoryPath) { . $spanFactoryPath }
    if (Test-Path $traceEnvelopePath) { . $traceEnvelopePath }
    if (Test-Path $otelBridgePath) { . $otelBridgePath }
}

Describe "SpanFactory Module Tests" {
    Context "New-TraceId and New-SpanId" {
        It "Should generate a 32-character lowercase hex trace ID" {
            $traceId = New-TraceId
            $traceId | Should -Not -BeNullOrEmpty
            $traceId | Should -Match "^[0-9a-f]{32}$"
        }

        It "Should generate a 16-character lowercase hex span ID" {
            $spanId = New-SpanId
            $spanId | Should -Not -BeNullOrEmpty
            $spanId | Should -Match "^[0-9a-f]{16}$"
        }

        It "Should generate unique trace IDs" {
            $ids = @()
            for ($i = 0; $i -lt 10; $i++) {
                $ids += New-TraceId
            }
            ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
        }

        It "Should generate unique span IDs" {
            $ids = @()
            for ($i = 0; $i -lt 10; $i++) {
                $ids += New-SpanId
            }
            ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
        }
    }

    Context "New-Span" {
        It "Should create a span with the given name" {
            $span = New-Span -Name "TestSpan"
            $span.name | Should -Be "TestSpan"
            $span.isStarted | Should -Be $false
            $span.isStopped | Should -Be $false
            $span.status | Should -Be "UNSET"
        }

        It "Should generate a new trace ID when none is provided" {
            $span = New-Span -Name "TestSpan"
            $span.traceId | Should -Not -BeNullOrEmpty
            $span.traceId | Should -Match "^[0-9a-f]{32}$"
        }

        It "Should use the provided trace ID" {
            $traceId = New-TraceId
            $span = New-Span -Name "TestSpan" -TraceId $traceId
            $span.traceId | Should -Be $traceId
        }

        It "Should store the parent span ID" {
            $parentSpanId = New-SpanId
            $span = New-Span -Name "TestSpan" -ParentSpanId $parentSpanId
            $span.parentSpanId | Should -Be $parentSpanId
        }

        It "Should store the correlation ID" {
            $span = New-Span -Name "TestSpan" -CorrelationId "corr-123"
            $span.correlationId | Should -Be "corr-123"
        }

        It "Should initialize attributes from parameters" {
            $span = New-Span -Name "TestSpan" -Attributes @{ "key1" = "value1"; "key2" = 42 }
            $span.attributes["key1"] | Should -Be "value1"
            $span.attributes["key2"] | Should -Be 42
        }
    }

    Context "Start-Span and Stop-Span" {
        It "Should set start time when started" {
            $span = New-Span -Name "TestSpan" | Start-Span
            $span.isStarted | Should -Be $true
            $span.startTime | Should -Not -BeNullOrEmpty
        }

        It "Should set end time and status when stopped" {
            $span = New-Span -Name "TestSpan" | Start-Span | Stop-Span -Status OK
            $span.isStopped | Should -Be $true
            $span.endTime | Should -Not -BeNullOrEmpty
            $span.status | Should -Be "OK"
        }

        It "Should throw when stopping a span that is not started" {
            $span = New-Span -Name "TestSpan"
            { Stop-Span -Span $span } | Should -Throw -ExpectedMessage "*not been started*"
        }

        It "Should throw when starting a span that is already stopped" {
            $span = New-Span -Name "TestSpan" | Start-Span | Stop-Span
            { Start-Span -Span $span } | Should -Throw -ExpectedMessage "*already been stopped*"
        }
    }

    Context "Add-SpanAttribute" {
        It "Should add an attribute to a span" {
            $span = New-Span -Name "TestSpan" | Add-SpanAttribute -Key "attr1" -Value "val1"
            $span.attributes["attr1"] | Should -Be "val1"
        }

        It "Should update an existing attribute" {
            $span = New-Span -Name "TestSpan" -Attributes @{ "attr1" = "old" }
            $span = $span | Add-SpanAttribute -Key "attr1" -Value "new"
            $span.attributes["attr1"] | Should -Be "new"
        }

        It "Should throw on empty key" {
            $span = New-Span -Name "TestSpan"
            { Add-SpanAttribute -Span $span -Key "" -Value "val" } | Should -Throw -ExpectedMessage "*Cannot bind argument to parameter 'Key'*"
        }
    }

    Context "Add-SpanEvent" {
        It "Should add an event to a span" {
            $span = New-Span -Name "TestSpan" | Add-SpanEvent -Name "event1"
            $span.events.Count | Should -Be 1
            $span.events[0].name | Should -Be "event1"
        }

        It "Should add an event with attributes" {
            $span = New-Span -Name "TestSpan" | Add-SpanEvent -Name "event1" -Attributes @{ "k" = "v" }
            $span.events[0].attributes["k"] | Should -Be "v"
        }

        It "Should throw on empty event name" {
            $span = New-Span -Name "TestSpan"
            { Add-SpanEvent -Span $span -Name "" } | Should -Throw -ExpectedMessage "*Cannot bind argument to parameter 'Name'*"
        }
    }
}

Describe "TraceEnvelope Module Tests" {
    Context "New-TraceEnvelope" {
        It "Should create an envelope from a span" {
            $span = New-Span -Name "TestSpan" -TraceId (New-TraceId) -CorrelationId "corr-abc" | Start-Span | Stop-Span
            $envelope = New-TraceEnvelope -Span $span
            $envelope.name | Should -Be $span.name
            $envelope.traceId | Should -Be $span.traceId
            $envelope.spanId | Should -Be $span.spanId
            $envelope.correlationId | Should -Be "corr-abc"
            $envelope.schemaVersion | Should -Be 1
            $envelope.isClosed | Should -Be $false
        }

        It "Should create an envelope from raw parameters" {
            $envelope = New-TraceEnvelope -TraceId (New-TraceId) -SpanId (New-SpanId) -Name "RawEnvelope"
            $envelope.name | Should -Be "RawEnvelope"
            $envelope.status | Should -Be "UNSET"
        }

        It "Should throw when span is null in FromSpan mode" {
            { New-TraceEnvelope -Span $null } | Should -Throw -ExpectedMessage "*cannot be null*"
        }
    }

    Context "Add-TraceEvent" {
        It "Should add an event to the envelope" {
            $envelope = New-TraceEnvelope -TraceId (New-TraceId) -SpanId (New-SpanId) -Name "TestEnvelope"
            $envelope = $envelope | Add-TraceEvent -Name "eval.scored" -Attributes @{ score = 0.95 }
            $envelope.events.Count | Should -Be 1
            $envelope.events[0].name | Should -Be "eval.scored"
            $envelope.events[0].attributes.score | Should -Be 0.95
        }
    }

    Context "Close-TraceEnvelope" {
        It "Should set end time and status when closed" {
            $envelope = New-TraceEnvelope -TraceId (New-TraceId) -SpanId (New-SpanId) -Name "TestEnvelope"
            $envelope = $envelope | Close-TraceEnvelope -Status OK
            $envelope.isClosed | Should -Be $true
            $envelope.status | Should -Be "OK"
            $envelope.endTime | Should -Not -BeNullOrEmpty
        }

        It "Should not modify already closed envelope" {
            $envelope = New-TraceEnvelope -TraceId (New-TraceId) -SpanId (New-SpanId) -Name "TestEnvelope"
            $envelope = $envelope | Close-TraceEnvelope -Status OK
            $firstEndTime = $envelope.endTime
            Start-Sleep -Milliseconds 50
            $envelope = $envelope | Close-TraceEnvelope -Status ERROR
            $envelope.endTime | Should -Be $firstEndTime
        }
    }
}

Describe "OpenTelemetryBridge Module Tests" {
    Context "New-OTelTrace" {
        It "Should create a trace context with a valid trace ID" {
            $ctx = New-OTelTrace
            $ctx.traceId | Should -Not -BeNullOrEmpty
            $ctx.traceId | Should -Match "^[0-9a-f]{32}$"
            $ctx.createdAt | Should -Not -BeNullOrEmpty
        }

        It "Should use the provided trace ID" {
            $traceId = New-TraceId
            $ctx = New-OTelTrace -TraceId $traceId
            $ctx.traceId | Should -Be $traceId
        }

        It "Should store correlation and parent span IDs" {
            $ctx = New-OTelTrace -CorrelationId "run-001" -ParentSpanId "deadbeefdeadbeef"
            $ctx.correlationId | Should -Be "run-001"
            $ctx.parentSpanId | Should -Be "deadbeefdeadbeef"
        }

        It "Should copy base attributes" {
            $ctx = New-OTelTrace -Attributes @{ "service" = "test" }
            $ctx.attributes["service"] | Should -Be "test"
        }
    }

    Context "ConvertTo-OTelPayload" {
        It "Should produce a resourceSpans wrapper" {
            $span = New-Span -Name "TestSpan" -TraceId (New-TraceId) | Start-Span | Stop-Span
            $payload = ConvertTo-OTelPayload -Span $span
            $payload.resourceSpans | Should -Not -BeNullOrEmpty
            $payload.resourceSpans[0].resource.attributes | Should -Not -BeNullOrEmpty
            $payload.resourceSpans[0].scopeSpans[0].spans[0].name | Should -Be "TestSpan"
        }
    }

    Context "ConvertTo-OTelAttributes" {
        It "Should map string values to stringValue" {
            $attrs = ConvertTo-OTelAttributes -Attributes @{ "s" = "hello" }
            $attrs[0].key | Should -Be "s"
            $attrs[0].value.stringValue | Should -Be "hello"
        }

        It "Should map numeric values to doubleValue" {
            $attrs = ConvertTo-OTelAttributes -Attributes @{ "n" = 42 }
            $attrs[0].value.doubleValue | Should -Be 42.0
        }

        It "Should map boolean values to boolValue" {
            $attrs = ConvertTo-OTelAttributes -Attributes @{ "b" = $true }
            $attrs[0].value.boolValue | Should -Be $true
        }
    }

    Context "ConvertTo-UnixTimeNano" {
        It "Should convert an ISO 8601 string to nanoseconds" {
            $iso = "2026-04-13T10:00:00.0000000Z"
            $nano = ConvertTo-UnixTimeNano -IsoString $iso
            $nano | Should -Not -BeNullOrEmpty
            $nano | Should -BeGreaterThan 0
        }

        It "Should return null for an empty string" {
            ConvertTo-UnixTimeNano -IsoString "" | Should -BeNullOrEmpty
        }
    }
}
