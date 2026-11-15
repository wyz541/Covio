$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$PreviousDir = Join-Path $Root "build\windows-previous"
$CurrentDir = Join-Path $Root "build\windows-package"
$ComposeDir = Join-Path $Root "build\windows-compose-package"

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
Remove-Item -Recurse -Force -Path $TestRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $TestRoot, $LogDir | Out-Null

function Invoke-Installer {
    param(
        [System.IO.FileInfo]$Installer,
        [string]$Label,
        [string]$Directory = $InstallDir
    )
    $log = Join-Path $LogDir "$Label.log"
    $process = Start-Process -FilePath $Installer.FullName -ArgumentList @(
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/SP-",
        "/DIR=`"$Directory`"",
        "/LOG=`"$log`""
    ) -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Installer $Label failed with exit code $($process.ExitCode)"
    }
}

function Get-BuildInfo {
    param([string]$Directory = $InstallDir)
    $path = Join-Path $Directory "build-info.txt"
    if (-not (Test-Path $path)) {
        throw "Installed build-info.txt is missing"
    }
    return (Get-Content $path -Raw)
}

function Assert-BuildNumber {
    param([int]$Expected, [string]$Directory = $InstallDir)
    $info = Get-BuildInfo -Directory $Directory
    if ($info -notmatch "buildNumber=$Expected") {
        throw "Expected installed build $Expected"
    }
}

function Invoke-Covio {
    param(
        [string[]]$Arguments,
        [int]$ExpectedExitCode = 0,
        [string]$Directory = $InstallDir
    )
    if (-not (Test-Path $Directory)) {
        throw "Installed Covio directory is missing"
    }
    $exe = Get-ChildItem $Directory -Filter "Covio.exe" -Recurse -File | Select-Object -First 1
    if ($null -eq $exe) {
        throw "Installed Covio.exe is missing"
    }
    $process = Start-Process -FilePath $exe.FullName -ArgumentList $Arguments -Wait -PassThru
    if ($process.ExitCode -ne $ExpectedExitCode) {
        throw "Covio exited with $($process.ExitCode), expected $ExpectedExitCode"
    }
}

function Uninstall-Covio {
    param([string]$Directory = $InstallDir)
    if (-not (Test-Path $Directory)) {
        throw "Uninstall directory is missing"
    }
    $uninstaller = Get-ChildItem $Directory -Filter "unins*.exe" | Select-Object -First 1
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
    if (Get-ChildItem $Directory -Filter "Covio.exe" -Recurse -File | Select-Object -First 1) {
        throw "Covio.exe remained after uninstall"
    }
}

function Assert-NoCovioExecutable {
    param([string]$Directory)
    if ((Test-Path $Directory) -and (Get-ChildItem $Directory -Filter "Covio.exe" -Recurse -File | Select-Object -First 1)) {
        throw "Covio.exe remained in $Directory"
    }
}

function Invoke-Msi {
    param(
        [string]$Msi,
        [string]$Action,
        [string]$Label,
        [string]$Directory
    )
    $log = Join-Path $LogDir "$Label.log"
    $arguments = "/$Action `"$Msi`" /qn /norestart /L*v `"$log`""
    if ($Action -eq "i") {
        $arguments += " INSTALLDIR=`"$Directory`""
    }
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "MSI $Label failed with exit code $($process.ExitCode)"
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

    $ComposeMetadataPath = Join-Path $ComposeDir "compose-package.json"
    if (-not (Test-Path $ComposeMetadataPath)) {
        throw "Missing Compose package metadata"
    }
    $ComposeMetadata = Get-Content $ComposeMetadataPath -Raw | ConvertFrom-Json
    if ($ComposeMetadata.schemaVersion -ne 2) {
        throw "Compose package schemaVersion must be 2"
    }
    if ($ComposeMetadata.defaultHost -ne "compose" -or $ComposeMetadata.rollbackHost -ne "egui") {
        throw "Compose package host metadata is invalid"
    }
    $ComposeMsi = Join-Path $ComposeDir $ComposeMetadata.artifacts.msi.name
    $RollbackInstallerPath = Join-Path $ComposeDir $ComposeMetadata.artifacts.rollback.name
    if (-not (Test-Path $ComposeMsi)) {
        throw "Missing Compose MSI"
    }
    if (-not (Test-Path $RollbackInstallerPath)) {
        throw "Missing packaged egui rollback installer"
    }

    $ComposeInstallDir = Join-Path $TestRoot "compose-app"
    $ComposeDataDir = Join-Path $TestRoot "compose-data"
    New-Item -ItemType Directory -Force -Path $ComposeDataDir | Out-Null
    Invoke-Msi -Msi $ComposeMsi -Action "i" -Label "compose-install" -Directory $ComposeInstallDir
    Invoke-Covio -Directory $ComposeInstallDir -Arguments @(
        "--headless-smoke",
        "--data-dir", "`"$ComposeDataDir`""
    )
    Invoke-Msi -Msi $ComposeMsi -Action "x" -Label "compose-uninstall"
    Assert-NoCovioExecutable -Directory $ComposeInstallDir

    Invoke-Installer -Installer (Get-Item $RollbackInstallerPath) -Label "compose-rollback-install" -Directory $ComposeInstallDir
    Assert-BuildNumber $ComposeMetadata.buildNumber -Directory $ComposeInstallDir
    Invoke-Covio -Directory $ComposeInstallDir -Arguments @(
        "--headless-smoke",
        "--data-dir", "`"$ComposeDataDir`""
    )
    Uninstall-Covio -Directory $ComposeInstallDir

    $report = '{"cleanInstall":true,"upgrade":true,"crashRecovery":true,"rollback":true,"uninstall":true,"dpiScale":1.5,"composeCleanInstall":true,"composeJniLoad":true,"rollbackHost":"egui","sharedData":true}'
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
    if ($ComposeInstallDir -and (Test-Path $ComposeInstallDir)) {
        $composeUninstaller = Get-ChildItem $ComposeInstallDir -Filter "unins*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $composeUninstaller) {
            $process = Start-Process -FilePath $composeUninstaller.FullName -ArgumentList @(
                "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-"
            ) -Wait -PassThru
            if ($process.ExitCode -ne 0) {
                Write-Warning "Compose cleanup uninstall failed with exit code $($process.ExitCode)"
            }
        } elseif ($ComposeMsi -and (Test-Path $ComposeMsi)) {
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$ComposeMsi`" /qn /norestart" -Wait -PassThru
            if ($process.ExitCode -notin @(0, 1605, 3010)) {
                Write-Warning "Compose MSI cleanup failed with exit code $($process.ExitCode)"
            }
        }
    }
}
