$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "performance\windows_benchmark.ps1"
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $path),
    [ref]$tokens,
    [ref]$errors
) | Out-Null
if ($errors.Count -gt 0) {
    $errors | Format-List | Out-String | Write-Error
    exit 1
}

$command = Get-Command $path
foreach ($parameterName in @("BaselinePath", "CandidatePath")) {
    $mandatory = ($command.Parameters[$parameterName].Attributes |
        Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory
    if ($mandatory) {
        throw "$parameterName must be optional for single-app mode."
    }
}

$content = Get-Content -LiteralPath $path -Raw
foreach ($marker in @("single-app", "Get-AppSummary", "summary.md", "PROCESSOR_ARCHITECTURE")) {
    if (-not $content.Contains($marker)) {
        throw "Windows performance benchmark is missing $marker."
    }
}

Write-Output "Windows performance benchmark tests passed."
