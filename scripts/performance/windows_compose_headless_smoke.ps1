param(
    [Parameter(Mandatory = $true)]
    [string]$AppExecutable,
    [Parameter(Mandatory = $true)]
    [string]$DataDirectory,
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = "Stop"
if (-not $IsWindows) {
    throw "windows_compose_headless_smoke.ps1 requires Windows."
}
if (-not (Test-Path -LiteralPath $AppExecutable)) {
    throw "Compose executable is missing: $AppExecutable"
}
New-Item -ItemType Directory -Force -Path $DataDirectory | Out-Null
$stdoutPath = Join-Path $DataDirectory "headless-stdout.log"
$stderrPath = Join-Path $DataDirectory "headless-stderr.log"
$process = Start-Process -FilePath $AppExecutable -PassThru `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -ArgumentList @("--headless-smoke", "--data-dir", $DataDirectory)
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
    $stdout = if (Test-Path -LiteralPath $stdoutPath) {
        Get-Content -LiteralPath $stdoutPath -Raw
    } else { "" }
    $stderr = if (Test-Path -LiteralPath $stderrPath) {
        Get-Content -LiteralPath $stderrPath -Raw
    } else { "" }
    throw "Compose headless smoke timed out. stdout=$stdout stderr=$stderr"
}
if ($process.ExitCode -ne 0) {
    $stdout = if (Test-Path -LiteralPath $stdoutPath) {
        Get-Content -LiteralPath $stdoutPath -Raw
    } else { "" }
    $stderr = if (Test-Path -LiteralPath $stderrPath) {
        Get-Content -LiteralPath $stderrPath -Raw
    } else { "" }
    throw "Compose headless smoke failed with exit code $($process.ExitCode). stdout=$stdout stderr=$stderr"
}
Write-Host "Compose headless smoke passed"
