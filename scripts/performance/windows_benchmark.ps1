param(
    [Parameter(Mandatory = $true)][string]$BaselinePath,
    [Parameter(Mandatory = $true)][string]$CandidatePath,
    [string]$BaselineLabel = "baseline",
    [string]$CandidateLabel = "candidate",
    [int]$Runs = 5,
    [int]$SettleSeconds = 25,
    [int]$SampleSeconds = 5,
    [int]$LaunchTimeoutSeconds = 30,
    [string]$OutputDirectory = "build\performance\windows",
    [switch]$KeepHomes
)

$ErrorActionPreference = "Stop"
if (-not $IsWindows) {
    throw "windows_benchmark.ps1 requires Windows 11 x64."
}
if (-not (Test-Path -LiteralPath $BaselinePath)) {
    throw "Baseline path does not exist: $BaselinePath"
}
if (-not (Test-Path -LiteralPath $CandidatePath)) {
    throw "Candidate path does not exist: $CandidatePath"
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

function Get-DescendantProcesses([int]$RootPid) {
    $all = Get-CimInstance Win32_Process
    $children = @{}
    foreach ($process in $all) {
        if (-not $children.ContainsKey([int]$process.ParentProcessId)) {
            $children[[int]$process.ParentProcessId] = @()
        }
        $children[[int]$process.ParentProcessId] += [int]$process.ProcessId
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
        function Median([object[]]$Values) {
            $sorted = @($Values | Sort-Object)
            if ($sorted.Count -eq 0) { return $null }
            $middle = [int][Math]::Floor($sorted.Count / 2)
            if ($sorted.Count % 2 -eq 1) { return $sorted[$middle] }
            return ($sorted[$middle - 1] + $sorted[$middle]) / 2.0
        }
        return [pscustomobject]@{
            label = $Label
            run = $Run
            status = "ok"
            launchMs = $launchMs
            rssBytes = Median @($samples.rssBytes)
            privateBytes = Median @($samples.privateBytes)
            cpuPercent = ($samples | Measure-Object -Property cpuPercent -Average).Average
            threads = Median @($samples.threads)
            handles = Median @($samples.handles)
            processCount = Median @($samples.processCount)
        }
    } finally {
        if ($null -ne $process) { Stop-AppTree -RootPid $process.Id }
        $env:LOCALAPPDATA = $oldLocalAppData
        $env:APPDATA = $oldAppData
        if (-not $KeepHomes) { Remove-Item -Recurse -Force -LiteralPath $runRoot -ErrorAction SilentlyContinue }
    }
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$baselineExecutable = Resolve-AppExecutable $BaselinePath
$candidateExecutable = Resolve-AppExecutable $CandidatePath
$apps = @(
    [pscustomobject]@{ label = $BaselineLabel; executable = $baselineExecutable; path = (Get-Item $BaselinePath).FullName },
    [pscustomobject]@{ label = $CandidateLabel; executable = $candidateExecutable; path = (Get-Item $CandidatePath).FullName }
)

foreach ($app in $apps) {
    Measure-App -Label $app.label -Executable $app.executable -Run 0 -MeasureSteady $false | Out-Null
}

$rows = @()
for ($run = 1; $run -le $Runs; $run++) {
    $ordered = if ($run % 2 -eq 0) { @($apps[1], $apps[0]) } else { $apps }
    foreach ($app in $ordered) {
        $row = Measure-App -Label $app.label -Executable $app.executable -Run $run -MeasureSteady $true
        $rows += $row
        Write-Host "$($app.label) run ${run}: $($row.status)"
    }
}

$csvPath = Join-Path $OutputDirectory "results.csv"
$jsonPath = Join-Path $OutputDirectory "results.json"
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvPath
$result = [pscustomobject]@{
    schemaVersion = 1
    generatedAt = [DateTime]::UtcNow.ToString("o")
    quality = if (@($rows | Where-Object status -eq "ok").Count -ge ($Runs * 2)) { "complete" } else { "partial" }
    environment = [pscustomobject]@{
        platform = "Windows"
        os = [System.Environment]::OSVersion.VersionString
        architecture = $env:PROCESSOR_ARCHITECTURE
        processorCount = [Environment]::ProcessorCount
        machine = $env:COMPUTERNAME
    }
    config = [pscustomobject]@{
        runs = $Runs
        settleSeconds = $SettleSeconds
        sampleSeconds = $SampleSeconds
    }
    apps = $apps
    runs = $rows
}
$result | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $jsonPath
Write-Host "Windows performance results: $OutputDirectory"
