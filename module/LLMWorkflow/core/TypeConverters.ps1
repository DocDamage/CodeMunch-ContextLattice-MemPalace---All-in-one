# Canonical type conversion helpers for LLMWorkflow

function ConvertTo-Hashtable {
    <#
    .SYNOPSIS
        Recursively converts a PSCustomObject to a Hashtable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )

    process {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @()
            foreach ($item in $InputObject) {
                $collection += (ConvertTo-Hashtable -InputObject $item)
            }
            return $collection
        }

        if ($InputObject -is [PSCustomObject] -or $InputObject -is [System.Management.Automation.PSCustomObject]) {
            $hash = @{}
            foreach ($prop in $InputObject.PSObject.Properties) {
                $hash[$prop.Name] = ConvertTo-Hashtable -InputObject $prop.Value
            }
            return $hash
        }

        return $InputObject
    }
}

function Convert-PSObjectToHashtable {
    <#
    .SYNOPSIS
        Alias for ConvertTo-Hashtable for backward compatibility.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )
    process {
        return ConvertTo-Hashtable -InputObject $InputObject
    }
}