param(
    [string]$BaselinePath = "",
    [string]$CandidatePath = "",
    [string]$BaselineLabel = "baseline",
    [string]$CandidateLabel = "candidate",
    [int]$Runs = 10,
    [int]$SettleSeconds = 30,
    [int]$SampleSeconds = 5,
    [int]$LaunchTimeoutSeconds = 30,
    [string]$OutputDirectory = "build\performance\windows",
    [switch]$KeepHomes
)

$ErrorActionPreference = "Stop"

if (-not $IsWindows) {
    throw "windows_benchmark.ps1 requires Windows 11 x64."
}
$architecture = if ($env:PROCESSOR_ARCHITEW6432) {
    $env:PROCESSOR_ARCHITEW6432
} else {
    $env:PROCESSOR_ARCHITECTURE
}
if ($architecture -ne "AMD64") {
    throw "windows_benchmark.ps1 requires Windows x64; found $architecture."
}
$operatingSystem = Get-CimInstance Win32_OperatingSystem
if ([int]$operatingSystem.BuildNumber -lt 22000) {
    throw "windows_benchmark.ps1 requires Windows 11 or newer."
}
if (-not $BaselinePath -and -not $CandidatePath) {
    throw "Specify -BaselinePath, -CandidatePath, or both."
}
if ($Runs -lt 1 -or $SampleSeconds -lt 1 -or $SettleSeconds -lt 0) {
    throw "Runs and sample seconds must be positive; settle seconds must be non-negative."
}
if ($BaselinePath -and -not (Test-Path -LiteralPath $BaselinePath)) {
    throw "Baseline path does not exist: $BaselinePath"
}
if ($CandidatePath -and -not (Test-Path -LiteralPath $CandidatePath)) {
    throw "Candidate path does not exist: $CandidatePath"
}
if ($BaselinePath -and $CandidatePath -and $BaselineLabel -eq $CandidateLabel) {
    throw "Baseline and candidate labels must differ."
}

function Resolve-AppExecutable([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) {
        $candidates = @(
            (Join-Path $item.FullName "Covio.exe"),
            (Join-Path $item.FullName "covio.exe"),
            (Join-Path $item.FullName "Covio.Windows.exe")
        )
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate) {
                return (Get-Item -LiteralPath $candidate).FullName
            }
        }
        throw "No Covio executable found in $Path"
    }
    return $item.FullName
}

function Get-AppIdentity([string]$Executable) {
    $file = Get-Item -LiteralPath $Executable
    $version = $file.VersionInfo
    return [pscustomobject]@{
        fileVersion = $version.FileVersion
        productVersion = $version.ProductVersion
        description = $version.FileDescription
        bytes = $file.Length
        sha256 = (Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-DescendantProcesses([int]$RootPid) {
    $all = Get-CimInstance Win32_Process
    $children = @{}
    foreach ($process in $all) {
        $parent = [int]$process.ParentProcessId
        if (-not $children.ContainsKey($parent)) {
            $children[$parent] = @()
        }
        $children[$parent] += [int]$process.ProcessId
    }
    $result = @()
    $pending = [System.Collections.Generic.Queue[int]]::new()
    $pending.Enqueue($RootPid)
    $seen = @{}
    while ($pending.Count -gt 0) {
        $pidValue = $pending.Dequeue()
        if ($seen.ContainsKey($pidValue)) { continue }
        $seen[$pidValue] = $true
        $result += $pidValue
        if ($children.ContainsKey($pidValue)) {
            foreach ($child in $children[$pidValue]) {
                $pending.Enqueue($child)
            }
        }
    }
    return $result
}

function Get-TreeMetrics([int]$RootPid) {
    $pids = Get-DescendantProcesses -RootPid $RootPid
    $processes = @(Get-Process -Id $pids -ErrorAction SilentlyContinue)
    $cpuSeconds = 0.0
    $handles = 0
    $threads = 0
    $workingSet = 0
    $privateBytes = 0
    foreach ($process in $processes) {
        $process.Refresh()
        $cpuSeconds += [double]$process.CPU
        $handles += [int]$process.HandleCount
        $threads += [int]$process.Threads.Count
        $workingSet += [int64]$process.WorkingSet64
        $privateBytes += [int64]$process.PrivateMemorySize64
    }
    return [pscustomobject]@{
        rssBytes = $workingSet
        privateBytes = $privateBytes
        cpuSeconds = $cpuSeconds
        threads = $threads
        handles = $handles
        processCount = $processes.Count
    }
}

function Stop-AppTree([int]$RootPid) {
    if (Get-Process -Id $RootPid -ErrorAction SilentlyContinue) {
        & taskkill.exe /PID $RootPid /T /F | Out-Null
    }
}

function Wait-MainWindow($Process, [int]$TimeoutSeconds) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $Process.Refresh()
            if ($Process.HasExited) { return $false }
            if ($Process.MainWindowHandle -ne 0) { return $true }
        } catch {
            return $false
        }
        Start-Sleep -Milliseconds 50
    }
    return $false
}

function Get-Median([object[]]$Values) {
    $sorted = @($Values | Where-Object { $null -ne $_ } | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) { return $sorted[$middle] }
    return ($sorted[$middle - 1] + $sorted[$middle]) / 2.0
}

function Measure-App(
    [string]$Label,
    [string]$Executable,
    [int]$Run,
    [bool]$MeasureSteady
) {
    $safeLabel = $Label -replace "[^A-Za-z0-9_.-]", "-"
    $runRoot = Join-Path $OutputDirectory "homes\$safeLabel-$Run"
    $localAppData = Join-Path $runRoot "LocalAppData"
    $appData = Join-Path $runRoot "AppData"
    New-Item -ItemType Directory -Force -Path $localAppData, $appData | Out-Null
    $oldLocalAppData = $env:LOCALAPPDATA
    $oldAppData = $env:APPDATA
    $started = [DateTime]::UtcNow
    $process = $null
    try {
        $env:LOCALAPPDATA = $localAppData
        $env:APPDATA = $appData
        $process = Start-Process -FilePath $Executable -PassThru
        $ready = Wait-MainWindow -Process $process -TimeoutSeconds $LaunchTimeoutSeconds
        $launchMs = ([DateTime]::UtcNow - $started).TotalMilliseconds
        if (-not $ready) {
            return [pscustomobject]@{
                label = $Label; run = $Run; status = "timeout"; launchMs = $launchMs
                rssBytes = $null; privateBytes = $null; cpuPercent = $null
                threads = $null; handles = $null; processCount = $null
            }
        }
        if (-not $MeasureSteady) {
            return [pscustomobject]@{
                label = $Label; run = $Run; status = "ok"; launchMs = $launchMs
                rssBytes = $null; privateBytes = $null; cpuPercent = $null
                threads = $null; handles = $null; processCount = $null
            }
        }
        Start-Sleep -Seconds $SettleSeconds
        $logical = [Environment]::ProcessorCount
        $samples = @()
        for ($index = 0; $index -lt $SampleSeconds; $index++) {
            $begin = [DateTime]::UtcNow
            $metrics = Get-TreeMetrics -RootPid $process.Id
            Start-Sleep -Seconds 1
            $after = Get-TreeMetrics -RootPid $process.Id
            $elapsed = ([DateTime]::UtcNow - $begin).TotalSeconds
            $cpuPercent = (($after.cpuSeconds - $metrics.cpuSeconds) / $elapsed / $logical) * 100.0
            $samples += [pscustomobject]@{
                rssBytes = $after.rssBytes
                privateBytes = $after.privateBytes
                cpuPercent = [Math]::Max(0.0, $cpuPercent)
                threads = $after.threads
                handles = $after.handles
                processCount = $after.processCount
            }
        }
        return [pscustomobject]@{
            label = $Label
            run = $Run
            status = "ok"
            launchMs = $launchMs
            rssBytes = Get-Median @($samples.rssBytes)
            privateBytes = Get-Median @($samples.privateBytes)
            cpuPercent = ($samples | Measure-Object -Property cpuPercent -Average).Average
            threads = Get-Median @($samples.threads)
            handles = Get-Median @($samples.handles)
            processCount = Get-Median @($samples.processCount)
        }
    } finally {
        if ($null -ne $process) { Stop-AppTree -RootPid $process.Id }
        $env:LOCALAPPDATA = $oldLocalAppData
        $env:APPDATA = $oldAppData
        if (-not $KeepHomes) { Remove-Item -Recurse -Force -LiteralPath $runRoot -ErrorAction SilentlyContinue }
    }
}

$metricNames = @(
    "launchMs",
    "rssBytes",
    "privateBytes",
    "cpuPercent",
    "threads",
    "handles",
    "processCount"
)

function Get-AppSummary($App, $Rows) {
    $all = @($Rows | Where-Object label -eq $App.label)
    $ok = @($all | Where-Object status -eq "ok")
    $metrics = [ordered]@{}
    foreach ($metric in $metricNames) {
        $values = @($ok | ForEach-Object { $_.$metric } | Where-Object { $null -ne $_ })
        $metrics[$metric] = [pscustomobject]@{
            count = $values.Count
            median = Get-Median $values
            min = if ($values.Count -gt 0) { ($values | Measure-Object -Minimum).Minimum } else { $null }
            max = if ($values.Count -gt 0) { ($values | Measure-Object -Maximum).Maximum } else { $null }
        }
    }
    return [pscustomobject]@{
        okRuns = $ok.Count
        totalRuns = $all.Count
        metrics = [pscustomobject]$metrics
    }
}

function Get-Comparison($Baseline, $Candidate) {
    $result = [ordered]@{}
    foreach ($metric in $metricNames) {
        $baseValue = $Baseline.metrics.$metric.median
        $candidateValue = $Candidate.metrics.$metric.median
        $delta = if ($null -ne $baseValue -and $null -ne $candidateValue) {
            $candidateValue - $baseValue
        } else {
            $null
        }
        $percent = if ($null -ne $baseValue -and $baseValue -ne 0 -and $null -ne $delta) {
            ($delta / $baseValue) * 100.0
        } else {
            $null
        }
        $result[$metric] = [pscustomobject]@{
            baselineMedian = $baseValue
            candidateMedian = $candidateValue
            deltaAbsolute = $delta
            deltaPercent = $percent
        }
    }
    return [pscustomobject]$result
}

function Format-Metric([string]$Metric, $Value) {
    if ($null -eq $Value) { return "n/a" }
    switch ($Metric) {
        "launchMs" { return ("{0:N3} ms" -f $Value) }
        "rssBytes" { return ("{0:N0} B" -f $Value) }
        "privateBytes" { return ("{0:N0} B" -f $Value) }
        "cpuPercent" { return ("{0:N3}%" -f $Value) }
        "threads" { return ("{0:N1}" -f $Value) }
        "handles" { return ("{0:N1}" -f $Value) }
        "processCount" { return ("{0:N1}" -f $Value) }
        default { return $Value }
    }
}

function Write-Summary(
    [string]$Path,
    [string]$Quality,
    $Environment,
    $Summaries,
    $Comparison,
    [int]$RequestedRuns
) {
    $lines = @(
        "# Covio Windows performance summary",
        "",
        "Data quality: **$Quality**",
        "",
        "## Environment",
        "",
        "| Field | Value |",
        "| --- | --- |",
        "| Machine | `$($Environment.machine)` |",
        "| OS | $($Environment.osCaption) $($Environment.osVersion) build $($Environment.osBuild) |",
        "| Architecture | `$($Environment.architecture)` |",
        "| Processor | $($Environment.processorName) |",
        "| Logical processors | $($Environment.logicalProcessors) |",
        "| Memory | $($Environment.memoryBytes) B |",
        "| Power plan | `$($Environment.powerPlan)` |",
        ""
    )
    if ($null -ne $Comparison) {
        $labels = @($Summaries.PSObject.Properties.Name)
        $lines += "## Median comparison"
        $lines += ""
        $lines += "| Metric | $($labels[0]) | $($labels[1]) | Change |"
        $lines += "| --- | ---: | ---: | ---: |"
        foreach ($metric in $metricNames) {
            $item = $Comparison.$metric
            $change = if ($null -eq $item.deltaPercent) { "n/a" } else { "{0:+0.00;-0.00;0.00}%" -f $item.deltaPercent }
            $lines += "| $metric | $(Format-Metric $metric $item.baselineMedian) | $(Format-Metric $metric $item.candidateMedian) | $change |"
        }
    } else {
        $label = @($Summaries.PSObject.Properties.Name)[0]
        $summary = $Summaries.$label
        $lines += "## $label"
        $lines += ""
        $lines += "| Metric | Median | Min | Max |"
        $lines += "| --- | ---: | ---: | ---: |"
        foreach ($metric in $metricNames) {
            $item = $summary.metrics.$metric
            $lines += "| $metric | $(Format-Metric $metric $item.median) | $(Format-Metric $metric $item.min) | $(Format-Metric $metric $item.max) |"
        }
    }
    $lines += ""
    $lines += "## Result files"
    $lines += ""
    $lines += "- results.csv"
    $lines += "- results.json"
    $lines += "- summary.md"
    $lines += "- requested runs: $RequestedRuns"
    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$specs = @()
if ($BaselinePath) { $specs += [pscustomobject]@{ label = $BaselineLabel; path = $BaselinePath } }
if ($CandidatePath) { $specs += [pscustomobject]@{ label = $CandidateLabel; path = $CandidatePath } }
$apps = @()
foreach ($spec in $specs) {
    $executable = Resolve-AppExecutable $spec.path
    $apps += [pscustomobject]@{
        label = $spec.label
        executable = $executable
        path = (Get-Item -LiteralPath $spec.path).FullName
        identity = Get-AppIdentity $executable
    }
}

foreach ($app in $apps) {
    Measure-App -Label $app.label -Executable $app.executable -Run 0 -MeasureSteady $false | Out-Null
}

$rows = [System.Collections.Generic.List[object]]::new()
for ($run = 1; $run -le $Runs; $run++) {
    $ordered = @($apps)
    if ($ordered.Count -eq 2 -and $run % 2 -eq 0) {
        $ordered = @($ordered[1], $ordered[0])
    }
    foreach ($app in $ordered) {
        $row = Measure-App -Label $app.label -Executable $app.executable -Run $run -MeasureSteady $true
        $rows.Add($row) | Out-Null
        Write-Host "$($app.label) run ${run}: $($row.status)"
    }
}

$summaryMap = [ordered]@{}
foreach ($app in $apps) {
    $summaryMap[$app.label] = Get-AppSummary $app $rows
}
$summaries = [pscustomobject]$summaryMap
$comparison = $null
if ($apps.Count -eq 2) {
    $comparison = Get-Comparison $summaries.$BaselineLabel $summaries.$CandidateLabel
}
$okCount = @($rows | Where-Object status -eq "ok").Count
$expectedCount = $Runs * $apps.Count
$quality = if ($okCount -eq $expectedCount) {
    if ($apps.Count -eq 1) { "single-app" } else { "complete" }
} elseif ($okCount -ge 3 * $apps.Count) {
    "partial"
} else {
    "insufficient"
}
$environment = [pscustomobject]@{
    platform = "Windows"
    machine = $env:COMPUTERNAME
    osCaption = $operatingSystem.Caption
    osVersion = $operatingSystem.Version
    osBuild = $operatingSystem.BuildNumber
    architecture = $architecture
    processorName = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
    logicalProcessors = [Environment]::ProcessorCount
    memoryBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    powerPlan = (powercfg /getactivescheme | Out-String).Trim()
}

$csvPath = Join-Path $OutputDirectory "results.csv"
$jsonPath = Join-Path $OutputDirectory "results.json"
$summaryPath = Join-Path $OutputDirectory "summary.md"
$rows | Export-Csv -NoTypeInformation -Encoding utf8 -Path $csvPath
$result = [pscustomobject]@{
    schemaVersion = 2
    generatedAt = [DateTime]::UtcNow.ToString("o")
    quality = $quality
    environment = $environment
    config = [pscustomobject]@{
        runs = $Runs
        settleSeconds = $SettleSeconds
        sampleSeconds = $SampleSeconds
    }
    apps = $apps
    summaries = $summaries
    comparison = $comparison
    runs = $rows
}
$result | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 -Path $jsonPath
Write-Summary -Path $summaryPath -Quality $quality -Environment $environment -Summaries $summaries -Comparison $comparison -RequestedRuns $Runs
Write-Host "Windows performance results: $OutputDirectory"
