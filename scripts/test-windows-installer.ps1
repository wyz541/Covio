$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$PreviousDir = Join-Path $Root "build\windows-previous"
$CurrentDir = Join-Path $Root "build\windows-package"

function Get-PackagedInstaller {
    param([string]$Directory, [string]$Label)
    $manifestPath = Join-Path $Directory "windows-package.json"
    if (-not (Test-Path $manifestPath)) {
        throw "Missing $Label package manifest"
    }
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $installerPath = Join-Path $Directory $manifest.artifact
    if (-not (Test-Path $installerPath)) {
        throw "Missing $Label installer"
    }
    return [pscustomobject]@{
        File = Get-Item $installerPath
        BuildNumber = [int]$manifest.buildNumber
    }
}

$PreviousPackage = Get-PackagedInstaller -Directory $PreviousDir -Label "previous"
$CurrentPackage = Get-PackagedInstaller -Directory $CurrentDir -Label "current"
$PreviousInstaller = $PreviousPackage.File
$CurrentInstaller = $CurrentPackage.File

$TestRoot = Join-Path $env:RUNNER_TEMP "covio-windows-installer"
$InstallDir = Join-Path $TestRoot "app"
$DataDir = Join-Path $TestRoot "data"
$CrashDataDir = Join-Path $TestRoot "crash-data"
$LogDir = Join-Path $TestRoot "logs"
New-Item -ItemType Directory -Force -Path $TestRoot, $LogDir | Out-Null

function Invoke-Installer {
    param([System.IO.FileInfo]$Installer, [string]$Label)
    $log = Join-Path $LogDir "$Label.log"
    $process = Start-Process -FilePath $Installer.FullName -ArgumentList @(
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/SP-",
        "/DIR=`"$InstallDir`"",
        "/LOG=`"$log`""
    ) -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Installer $Label failed with exit code $($process.ExitCode)"
    }
}

function Get-BuildInfo {
    $path = Join-Path $InstallDir "build-info.txt"
    if (-not (Test-Path $path)) {
        throw "Installed build-info.txt is missing"
    }
    return (Get-Content $path -Raw)
}

function Assert-BuildNumber {
    param([int]$Expected)
    $info = Get-BuildInfo
    if ($info -notmatch "buildNumber=$Expected") {
        throw "Expected installed build $Expected"
    }
}

function Invoke-Covio {
    param([string[]]$Arguments, [int]$ExpectedExitCode = 0)
    $exe = Join-Path $InstallDir "Covio.exe"
    if (-not (Test-Path $exe)) {
        throw "Installed Covio.exe is missing"
    }
    $process = Start-Process -FilePath $exe -ArgumentList $Arguments -Wait -PassThru
    if ($process.ExitCode -ne $ExpectedExitCode) {
        throw "Covio exited with $($process.ExitCode), expected $ExpectedExitCode"
    }
}

function Uninstall-Covio {
    $uninstaller = Get-ChildItem $InstallDir -Filter "unins*.exe" | Select-Object -First 1
    if ($null -eq $uninstaller) {
        throw "Uninstaller is missing"
    }
    $process = Start-Process -FilePath $uninstaller.FullName -ArgumentList @(
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/SP-"
    ) -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Uninstaller failed with exit code $($process.ExitCode)"
    }
    Start-Sleep -Milliseconds 500
    if (Test-Path (Join-Path $InstallDir "Covio.exe")) {
        throw "Covio.exe remained after uninstall"
    }
}

try {
    Invoke-Installer -Installer $PreviousInstaller -Label "previous-install"
    Assert-BuildNumber $PreviousPackage.BuildNumber
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    Invoke-Covio -Arguments @("--headless-smoke", "--data-dir", "`"$DataDir`"")

    Invoke-Installer -Installer $CurrentInstaller -Label "upgrade-install"
    Assert-BuildNumber $CurrentPackage.BuildNumber
    Invoke-Covio -Arguments @(
        "--window-smoke",
        "--ui-scale", "1.5",
        "--window-position", "0,0",
        "--data-dir", "`"$DataDir`""
    )

    New-Item -ItemType Directory -Force -Path $CrashDataDir | Out-Null
    Invoke-Covio -Arguments @(
        "--crash-recovery-smoke",
        "--data-dir", "`"$CrashDataDir`""
    ) -ExpectedExitCode 23
    Invoke-Covio -Arguments @("--headless-smoke", "--data-dir", "`"$CrashDataDir`"")

    Uninstall-Covio
    Invoke-Installer -Installer $PreviousInstaller -Label "rollback-install"
    Assert-BuildNumber $PreviousPackage.BuildNumber
    Invoke-Covio -Arguments @("--headless-smoke", "--data-dir", "`"$DataDir`"")
    Uninstall-Covio

    $report = '{"cleanInstall":true,"upgrade":true,"crashRecovery":true,"rollback":true,"uninstall":true,"dpiScale":1.5}'
    Set-Content -Path (Join-Path $CurrentDir "installer-test.json") -Value $report -Encoding utf8
    Write-Output $report
}
finally {
    $uninstaller = if (Test-Path $InstallDir) {
        Get-ChildItem $InstallDir -Filter "unins*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($null -ne $uninstaller) {
        $process = Start-Process -FilePath $uninstaller.FullName -ArgumentList @(
            "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-"
        ) -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            Write-Warning "Cleanup uninstall failed with exit code $($process.ExitCode)"
        }
    }
}
