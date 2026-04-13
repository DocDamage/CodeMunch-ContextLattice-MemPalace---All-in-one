#requires -Version 5.1
<#
.SYNOPSIS
    Unit tests for the RetrievalProfiles module.

.DESCRIPTION
    Tests all public functions of the RetrievalProfiles module to ensure
    correct behavior for built-in profiles and custom profile creation.
#>

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $projectRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = [System.IO.Path]::Combine($projectRoot, 'module', 'LLMWorkflow', 'retrieval', 'RetrievalProfiles.ps1')
    Import-Module $modulePath -Force
}

Describe 'Get-AllRetrievalProfiles' {
    It 'Returns array of profiles' {
        $profiles = Get-AllRetrievalProfiles
        $profiles | Should -Not -BeNullOrEmpty
        $profiles.Count | Should -Be 7
    }

    It 'Each profile has required fields' {
        $profiles = Get-AllRetrievalProfiles
        foreach ($p in $profiles) {
            $p.name | Should -Not -BeNullOrEmpty
            $p.description | Should -Not -BeNullOrEmpty
            $p.category | Should -Not -BeNullOrEmpty
        }
    }

    It 'All 7 built-in profiles present' {
        $profiles = Get-AllRetrievalProfiles
        $expected = @('api-lookup', 'plugin-pattern', 'conflict-diagnosis', 'codegen',
                      'private-project-first', 'tooling-workflow', 'reverse-format')
        foreach ($exp in $expected) {
            $profiles | Where-Object { $_.name -eq $exp } | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-RetrievalProfileConfig' {
    It 'Returns correct profile for api-lookup' {
        $profile = Get-RetrievalProfileConfig -ProfileName 'api-lookup'
        $profile | Should -Not -BeNullOrEmpty
        $profile.name | Should -Be 'api-lookup'
        $profile.minTrustTier | Should -Be 'high'
    }

    It 'Returns correct profile for plugin-pattern' {
        $profile = Get-RetrievalProfileConfig -ProfileName 'plugin-pattern'
        $profile | Should -Not -BeNullOrEmpty
        $profile.minTrustTier | Should -Be 'medium'
        $profile.requireMultipleSources | Should -Be $true
    }

    It 'Returns correct profile for conflict-diagnosis' {
        $profile = Get-RetrievalProfileConfig -ProfileName 'conflict-diagnosis'
        $profile | Should -Not -BeNullOrEmpty
        $profile.minTrustTier | Should -Be 'medium-high'
        $profile.config.crossSourceComparison | Should -Be $true
    }

    It 'Returns correct profile for codegen' {
        $profile = Get-RetrievalProfileConfig -ProfileName 'codegen'
        $profile | Should -Not -BeNullOrEmpty
        $profile.minTrustTier | Should -Be 'medium-high'
        $profile.config.multipleSourceAggregation | Should -Be $true
    }

    It 'Returns correct profile for private-project-first' {
        $profile = Get-RetrievalProfileConfig -ProfileName 'private-project-first'
        $profile | Should -Not -BeNullOrEmpty
        $profile.privateProjectFirst | Should -Be $true
        $profile.config.labelFallbacksExplicitly | Should -Be $true
    }

    It 'Returns correct profile for tooling-workflow' {
        $profile = Get-RetrievalProfileConfig -ProfileName 'tooling-workflow'
        $profile | Should -Not -BeNullOrEmpty
        $profile.minTrustTier | Should -Be 'medium'
    }

    It 'Returns correct profile for reverse-format' {
        $profile = Get-RetrievalProfileConfig -ProfileName 'reverse-format'
        $profile | Should -Not -BeNullOrEmpty
        $profile.config.specialHandlingDecompilation | Should -Be $true
    }

    It 'Returns null for nonexistent profile' {
        $profile = Get-RetrievalProfileConfig -ProfileName 'nonexistent-profile'
        $profile | Should -Be $null
    }

    It 'Profile config is a deep copy (modification does not affect original)' {
        $profile1 = Get-RetrievalProfileConfig -ProfileName 'api-lookup'
        $profile2 = Get-RetrievalProfileConfig -ProfileName 'api-lookup'
        $profile1.description = 'MODIFIED'
        $profile2.description | Should -Not -Be 'MODIFIED'
    }
}

Describe 'Test-RetrievalProfileExists' {
    It 'Returns true for built-in profiles' {
        Test-RetrievalProfileExists -ProfileName 'api-lookup' | Should -Be $true
        Test-RetrievalProfileExists -ProfileName 'codegen' | Should -Be $true
    }

    It 'Returns false for nonexistent profile' {
        Test-RetrievalProfileExists -ProfileName 'nonexistent' | Should -Be $false
    }

    It 'Case insensitive matching' {
        Test-RetrievalProfileExists -ProfileName 'API-LOOKUP' | Should -Be $true
        Test-RetrievalProfileExists -ProfileName 'Codegen' | Should -Be $true
    }
}

Describe 'Get-ProfilePackPreferences' {
    It 'Returns pack preferences for api-lookup' {
        $prefs = Get-ProfilePackPreferences -ProfileName 'api-lookup'
        $prefs | Should -Not -BeNullOrEmpty
        $prefs[0] | Should -Be 'core_api'
    }

    It 'Returns empty array for nonexistent profile' {
        $prefs = Get-ProfilePackPreferences -ProfileName 'nonexistent'
        ($prefs | Measure-Object).Count | Should -Be 0
    }

    It 'Filters against available packs when provided' {
        $available = @('core_api', 'tooling')
        $prefs = Get-ProfilePackPreferences -ProfileName 'api-lookup' -AvailablePacks $available
        $prefs | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-ProfileEvidenceTypes' {
    It 'Returns evidence types for codegen' {
        $types = Get-ProfileEvidenceTypes -ProfileName 'codegen'
        $types | Should -Not -BeNullOrEmpty
        $types | Should -Contain 'code-example'
    }

    It 'Returns correct evidence types for api-lookup' {
        $types = Get-ProfileEvidenceTypes -ProfileName 'api-lookup'
        $types | Should -Contain 'api-reference'
        $types | Should -Contain 'schema-definition'
    }
}

Describe 'New-CustomRetrievalProfile' {
    It 'Creates custom profile successfully' {
        $config = @{
            description = 'Test custom profile'
            packPreferences = @('pack1', 'pack2')
            evidenceTypes = @('code-example', 'configuration')
        }
        $profile = New-CustomRetrievalProfile -ProfileName 'test-custom' -Config $config
        $profile.name | Should -Be 'test-custom'
        $profile.description | Should -Be 'Test custom profile'
    }

    It 'Custom profile appears in Get-AllRetrievalProfiles' {
        Test-RetrievalProfileExists -ProfileName 'test-custom' | Should -Be $true
    }

    It 'Cannot create profile with empty name' {
        $config = @{ description = 'Test'; packPreferences = @('p1'); evidenceTypes = @('t1') }
        { New-CustomRetrievalProfile -ProfileName '' -Config $config } | Should -Throw
    }

    It 'Cannot create profile without description' {
        $config = @{ packPreferences = @('p1'); evidenceTypes = @('t1') }
        { New-CustomRetrievalProfile -ProfileName 'test-bad' -Config $config } | Should -Throw
    }

    It 'Cannot create profile without packPreferences' {
        $config = @{ description = 'Test'; evidenceTypes = @('t1') }
        { New-CustomRetrievalProfile -ProfileName 'test-bad' -Config $config } | Should -Throw
    }

    It 'Cannot create profile without evidenceTypes' {
        $config = @{ description = 'Test'; packPreferences = @('p1') }
        { New-CustomRetrievalProfile -ProfileName 'test-bad' -Config $config } | Should -Throw
    }

    It 'Cannot overwrite built-in profile' {
        $config = @{ description = 'Test'; packPreferences = @('p1'); evidenceTypes = @('t1') }
        { New-CustomRetrievalProfile -ProfileName 'api-lookup' -Config $config } | Should -Throw
    }
}

Describe 'Additional Utility Functions' {
    It 'Get-ProfileMinTrustTier returns correct value' {
        $tier = Get-ProfileMinTrustTier -ProfileName 'api-lookup'
        $tier | Should -Be 'high'
    }

    It 'Test-ProfileRequiresMultipleSources returns correct value' {
        $result = Test-ProfileRequiresMultipleSources -ProfileName 'plugin-pattern'
        $result | Should -Be $true

        $result = Test-ProfileRequiresMultipleSources -ProfileName 'api-lookup'
        $result | Should -Be $false
    }

    It 'Get-ProfileCategories returns categories' {
        $categories = Get-ProfileCategories
        $categories | Should -Not -BeNullOrEmpty
        $categories | Where-Object { $_.name -eq 'reference' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Profile Configuration Validation' {
    It 'api-lookup has requireAuthorityRole specified' {
        $profile = Get-RetrievalProfileConfig -ProfileName 'api-lookup'
        $profile.config.requireAuthorityRole | Should -Not -BeNullOrEmpty
    }

    It 'private-project-first has fallback configuration' {
        $profile = Get-RetrievalProfileConfig -ProfileName 'private-project-first'
        $profile.config.fallbackToPublic | Should -Be $true
        $profile.config.fallbackLabelFormat | Should -Not -BeNullOrEmpty
    }

    It 'reverse-format has deconfiguration settings' {
        $profile = Get-RetrievalProfileConfig -ProfileName 'reverse-format'
        $profile.config.warnOnLegalIssues | Should -Be $true
    }
}
