param(
    [Parameter(Mandatory = $true)]
    [string]$AppDirectory,
    [string]$PackageDirectory = "build\windows-compose-package",
    [string]$OutputDirectory = "build\performance\windows-compose",
    [int]$Runs = 5,
    [switch]$AccessibilityPassed
)

$ErrorActionPreference = "Stop"
if (-not $IsWindows) {
    throw "windows_compose_baseline.ps1 requires Windows."
}
if ($Runs -lt 1) {
    throw "Runs must be positive."
}
$exe = Join-Path $AppDirectory "Covio.exe"
if (-not (Test-Path -LiteralPath $exe)) {
    throw "Compose executable is missing: $exe"
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$runRoot = Join-Path $OutputDirectory "runs"
Remove-Item -Recurse -Force -LiteralPath $runRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

function Get-Median([object[]]$Values) {
    $items = @($Values | Where-Object { $null -ne $_ } | Sort-Object)
    if ($items.Count -eq 0) { return $null }
    $middle = [int][Math]::Floor($items.Count / 2)
    if ($items.Count % 2 -eq 1) { return [double]$items[$middle] }
    return ([double]$items[$middle - 1] + [double]$items[$middle]) / 2.0
}

$rows = @()
for ($run = 1; $run -le $Runs; $run++) {
    $dataDir = Join-Path $runRoot "data-$run"
    $resultPath = Join-Path $runRoot "metrics-$run.json"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    $startedUtc = [DateTime]::UtcNow
    $stdoutPath = Join-Path $runRoot "stdout-$run.log"
    $stderrPath = Join-Path $runRoot "stderr-$run.log"
    $process = Start-Process -FilePath $exe -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -ArgumentList @(
            "--baseline-result", $resultPath,
            "--data-dir", $dataDir,
            "--theme", "light",
            "--screen", "devices"
        )
    $peakWorkingSet = 0L
    $cpuStart = 0.0
    while (-not $process.HasExited) {
        try {
            $process.Refresh()
            $peakWorkingSet = [Math]::Max($peakWorkingSet, [int64]$process.WorkingSet64)
            $cpuStart = [Math]::Max($cpuStart, [double]$process.CPU)
        } catch {}
        if (([DateTime]::UtcNow - $startedUtc).TotalSeconds -gt 45) {
            & taskkill.exe /PID $process.Id /T /F | Out-Null
            $stdout = if (Test-Path -LiteralPath $stdoutPath) {
                (Get-Content -LiteralPath $stdoutPath -Raw)
            } else { "" }
            $stderr = if (Test-Path -LiteralPath $stderrPath) {
                (Get-Content -LiteralPath $stderrPath -Raw)
            } else { "" }
            throw "Compose baseline run timed out. stdout=$stdout stderr=$stderr"
        }
        Start-Sleep -Milliseconds 50
    }
    if ($process.ExitCode -ne 0) {
        $stderr = if (Test-Path -LiteralPath $stderrPath) {
            (Get-Content -LiteralPath $stderrPath -Raw)
        } else { "" }
        throw "Compose baseline run failed with exit code $($process.ExitCode): $stderr"
    }
    if (-not (Test-Path -LiteralPath $resultPath)) {
        throw "Compose baseline did not write metrics: $resultPath"
    }
    $metric = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $rows += [pscustomobject]@{
        run = $run
        coldStartMs = [double]$metric.cold_start_ms
        frameAverageMs = [double]$metric.frame_average_ms
        frameP95Ms = [double]$metric.frame_p95_ms
        frameMaxMs = [double]$metric.frame_max_ms
        heapUsedBytes = [int64]$metric.heap_used_bytes
        heapCommittedBytes = [int64]$metric.heap_committed_bytes
        nonHeapUsedBytes = [int64]$metric.non_heap_used_bytes
        committedVirtualBytes = [int64]$metric.committed_virtual_bytes
        sampledWorkingSetBytes = $peakWorkingSet
    }
}

$portable = Get-ChildItem -LiteralPath $PackageDirectory -Filter "Covio-*-windows-x64-portable.zip" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$runtime = Join-Path $PackageDirectory "runtime"
$runtimeBytes = 0L
if (Test-Path -LiteralPath $runtime) {
    $runtimeBytes = (Get-ChildItem -LiteralPath $runtime -File -Recurse | Measure-Object Length -Sum).Sum
}
$summary = [ordered]@{
    schemaVersion = 1
    generatedAt = [DateTime]::UtcNow.ToString("o")
    os = [System.Environment]::OSVersion.VersionString
    runs = $rows
    medians = [ordered]@{
        coldStartMs = Get-Median @($rows.coldStartMs)
        frameAverageMs = Get-Median @($rows.frameAverageMs)
        frameP95Ms = Get-Median @($rows.frameP95Ms)
        frameMaxMs = Get-Median @($rows.frameMaxMs)
        heapUsedBytes = Get-Median @($rows.heapUsedBytes)
        heapCommittedBytes = Get-Median @($rows.heapCommittedBytes)
        nonHeapUsedBytes = Get-Median @($rows.nonHeapUsedBytes)
        committedVirtualBytes = Get-Median @($rows.committedVirtualBytes)
        sampledWorkingSetBytes = Get-Median @($rows.sampledWorkingSetBytes)
    }
    package = [ordered]@{
        portableZipBytes = if ($null -eq $portable) { $null } else { $portable.Length }
        jlinkRuntimeBytes = $runtimeBytes
    }
    accessibility = [ordered]@{
        passed = [bool]$AccessibilityPassed
        checks = @("44dp targets", "content descriptions", "focus state", "light-theme contrast")
    }
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory "baseline.json") -Encoding utf8
$rows | Export-Csv -LiteralPath (Join-Path $OutputDirectory "runs.csv") -NoTypeInformation -Encoding utf8

$lines = @(
    "# Covio Windows Compose baseline",
    "",
    "| Metric | Median |",
    "| --- | ---: |",
    "| Cold start | $([Math]::Round($summary.medians.coldStartMs, 1)) ms |",
    "| Frame average | $([Math]::Round($summary.medians.frameAverageMs, 2)) ms |",
    "| Frame p95 | $([Math]::Round($summary.medians.frameP95Ms, 2)) ms |",
    "| Heap used | $([int64]$summary.medians.heapUsedBytes) B |",
    "| Working set sample | $([int64]$summary.medians.sampledWorkingSetBytes) B |",
    "| Portable ZIP | $($summary.package.portableZipBytes) B |",
    "| jlink runtime | $($summary.package.jlinkRuntimeBytes) B |",
    "| Accessibility | $($summary.accessibility.passed) |"
)
Set-Content -LiteralPath (Join-Path $OutputDirectory "summary.md") -Value $lines -Encoding utf8
Write-Host "Windows Compose baseline written to $OutputDirectory"
