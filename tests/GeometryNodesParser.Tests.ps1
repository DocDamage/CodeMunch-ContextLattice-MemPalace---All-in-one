#requires -Version 5.1

BeforeAll {
    $parserPath = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'module') 'LLMWorkflow') 'ingestion\parsers\GeometryNodesParser.ps1'
    . $parserPath
}

Describe 'GeometryNodesParser' {
    Context 'Invoke-GeometryNodesParse' {
        It 'Parses inline JSON node-tree content' {
            $json = @'
{
  "name": "GeoUnitTest",
  "nodeTreeType": "GeometryNodeTree",
  "nodes": [
    {
      "id": "in1",
      "type": "NodeGroupInput",
      "name": "Group Input",
      "inputs": [],
      "outputs": [
        { "identifier": "Geometry", "name": "Geometry", "type": "NodeSocketGeometry" }
      ]
    },
    {
      "id": "out1",
      "type": "NodeGroupOutput",
      "name": "Group Output",
      "inputs": [
        { "identifier": "Geometry", "name": "Geometry", "type": "NodeSocketGeometry" }
      ],
      "outputs": []
    }
  ],
  "links": [
    { "fromNode": "in1", "fromSocket": "Geometry", "toNode": "out1", "toSocket": "Geometry" }
  ],
  "inputs": [],
  "outputs": []
}
'@

            $result = Invoke-GeometryNodesParse -InputObject $json -InputType Auto

            $result | Should -Not -BeNullOrEmpty
            $result.name | Should -Be 'GeoUnitTest'
            $result.nodeTreeType | Should -Be 'GeometryNodeTree'
            $result.nodes.Count | Should -Be 2
            $result.links.Count | Should -Be 1
        }

        It 'Parses from file path and records resolved sourceFile' {
            $path = Join-Path $TestDrive 'geometry.json'
            '{"name":"FromFile","nodeTreeType":"GeometryNodeTree","nodes":[],"links":[]}' | Set-Content -LiteralPath $path -Encoding UTF8

            $result = Invoke-GeometryNodesParse -InputObject $path -InputType Auto
            $resolved = (Resolve-Path -LiteralPath $path).Path

            $result.name | Should -Be 'FromFile'
            $result.sourceFile | Should -Be $resolved
        }

        It 'Falls back to content parsing when file probe throws unexpectedly' {
            $candidate = 'C:\invalid\graph.py'
            Mock Test-Path { throw [System.IO.IOException]::new('probe failed') } -ParameterFilter { $LiteralPath -eq $candidate -and $PathType -eq 'Leaf' }

            { $script:result = Invoke-GeometryNodesParse -InputObject $candidate -InputType Auto } | Should -Not -Throw

            $script:result.name | Should -Be 'Unknown'
            $script:result.sourceFile | Should -Be ''
        }

        It 'Throws a clear error when a probed file cannot be resolved' {
            $script:virtualPath = 'C:\virtual\graph.py'
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $script:virtualPath -and $PathType -eq 'Leaf' }
            Mock Resolve-Path { throw [System.IO.IOException]::new('resolve failed') } -ParameterFilter { $LiteralPath -eq $script:virtualPath }

            { Invoke-GeometryNodesParse -InputObject $script:virtualPath -InputType Auto -ErrorAction SilentlyContinue } | Should -Throw '*Failed to resolve Geometry Nodes source file path*'
        }
    }
}
