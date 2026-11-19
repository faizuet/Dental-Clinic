# Starts Docker Desktop when it is stopped, then the existing clinic
# database and API, then the release desktop app.
# Existing Docker volumes are reused. This script does not delete data.
$ErrorActionPreference = 'Stop'
# PowerShell 7 turns a failed docker.exe call into a terminating error.
# A stopped engine must stay a normal startup step, not a crash.
try {
    $PSNativeCommandUseErrorActionPreference = $false
}
catch {
}

$repo = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $repo 'nabi-dental-backend'
$appDir = Join-Path $repo 'dist\Nabi Dental Clinic'
$appExe = Join-Path $appDir 'nabi_dental_app.exe'
$logDir = Join-Path $env:LOCALAPPDATA 'NabiDental'
$logFile = Join-Path $logDir 'launch.log'
$backupDir = Join-Path $logDir 'backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$env:NABI_BACKUP_DIR = $backupDir
$unattended = $env:NABI_LAUNCH_UNATTENDED -eq '1'
$engineWaitSeconds = 180
$serverWaitSeconds = 240
if ($env:NABI_ENGINE_WAIT_SECONDS -match '^\d+$') {
    $engineWaitSeconds = [int]$env:NABI_ENGINE_WAIT_SECONDS
}
if ($env:NABI_SERVER_WAIT_SECONDS -match '^\d+$') {
    $serverWaitSeconds = [int]$env:NABI_SERVER_WAIT_SECONDS
}

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Write-Log([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $logFile -Value $line
}

$form = $null
$status = $null
if (-not $unattended) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Nabi Dental Clinic'
    $form.ClientSize = New-Object System.Drawing.Size(460, 130)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ControlBox = $false
    $form.TopMost = $true
    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'Starting Nabi Dental Clinic...'
    $status.Font = New-Object System.Drawing.Font('Segoe UI', 12)
    $status.Dock = 'Fill'
    $status.TextAlign = 'MiddleLeft'
    $status.Padding = New-Object System.Windows.Forms.Padding(24, 0, 24, 0)
    $form.Controls.Add($status)
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Status([string]$Text) {
    Write-Log $Text
    if ($status) {
        $status.Text = $Text
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Show-Failure([string]$Text) {
    Write-Log "FAILED $Text"
    if ($unattended) {
        Set-Content -Path (Join-Path $logDir 'launch-result.txt') -Value $Text
        exit 1
    }
    if ($form -and -not $form.IsDisposed) {
        $form.Close()
    }
    [System.Windows.Forms.MessageBox]::Show($Text, 'Nabi Dental Clinic') | Out-Null
    exit 1
}

function Get-DockerDesktopExe {
    $candidates = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
    )
    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Get-DockerExe {
    if ($env:NABI_DOCKER_EXE -and (Test-Path $env:NABI_DOCKER_EXE)) {
        return $env:NABI_DOCKER_EXE
    }
    $command = Get-Command docker -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    $candidates = @(
        "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
    )
    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [int]$TimeoutSeconds = 20
    )
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $FileName
    $start.Arguments = $Arguments
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    if ($WorkingDirectory) {
        $start.WorkingDirectory = $WorkingDirectory
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
    }
    catch {
        return 1
    }
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try {
            $process.Kill()
        }
        catch {
        }
        return 1
    }
    return $process.ExitCode
}

function Test-DockerEngine {
    if ($env:NABI_ASSUME_ENGINE_DOWN -eq '1') {
        return $false
    }
    $docker = Get-DockerExe
    if (-not $docker) {
        return $false
    }
    return (Invoke-Native -FileName $docker -Arguments 'info' -TimeoutSeconds 8) -eq 0
}

function Test-ClinicReady {
    if ($env:NABI_ASSUME_SERVER_DOWN -eq '1') {
        return $false
    }
    try {
        $response = Invoke-WebRequest -Uri 'http://127.0.0.1:8001/ready' -UseBasicParsing -TimeoutSec 3
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Show-ClinicWindow {
    $running = @(Get-Process -Name 'nabi_dental_app' -ErrorAction SilentlyContinue)
    foreach ($process in $running) {
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            if (-not ('NabiWindow' -as [type])) {
                Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NabiWindow {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@
            }
            [void][NabiWindow]::ShowWindow($process.MainWindowHandle, 9)
            [void][NabiWindow]::SetForegroundWindow($process.MainWindowHandle)
            Write-Log 'Clinic window already open'
            return
        }
    }
    if ($running.Count -gt 0) {
        Write-Log 'Clinic process already running'
        return
    }
    Set-Status 'Opening the clinic...'
    Start-Process -FilePath $appExe -WorkingDirectory $appDir | Out-Null
    Write-Log 'Clinic window launched'
}

$mutex = New-Object System.Threading.Mutex($false, 'Local\NabiDentalClinicLauncher')
$ownsMutex = $false
try {
    try {
        $ownsMutex = $mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $ownsMutex = $true
    }
    if (-not $ownsMutex) {
        Write-Log 'Launcher already running'
        exit 0
    }

    $desktop = Get-DockerDesktopExe
    $docker = Get-DockerExe
    if (-not $desktop -and -not $docker) {
        Show-Failure 'Docker Desktop is not installed. Install Docker Desktop, open it once so it can finish setup, then open Nabi Dental Clinic again.'
    }
    if (-not (Test-Path $appExe)) {
        Show-Failure 'The Nabi Dental Clinic app is not installed on this computer. Ask the person who set up the clinic to restore the desktop app.'
    }

    if (-not (Test-DockerEngine)) {
        if (-not $desktop) {
            Show-Failure 'Docker Desktop is installed, but its program could not be found. Open Docker Desktop from the Start menu, wait until it says it is running, then open Nabi Dental Clinic again.'
        }
        Set-Status 'Opening Docker Desktop...'
        Start-Process -FilePath $desktop | Out-Null
        $deadline = (Get-Date).AddSeconds($engineWaitSeconds)
        $engineReady = $false
        while ((Get-Date) -lt $deadline) {
            if (Test-DockerEngine) {
                $engineReady = $true
                break
            }
            Set-Status 'Waiting for Docker Desktop to finish starting...'
            Start-Sleep -Seconds 2
        }
        if (-not $engineReady) {
            Show-Failure 'Docker Desktop is taking too long to start. Open Docker Desktop from the Start menu, wait until it says it is running, then open Nabi Dental Clinic again.'
        }
    }

    if (-not (Test-ClinicReady)) {
        Set-Status 'Starting the clinic database and server...'
        $docker = Get-DockerExe
        if (-not $docker) {
            Show-Failure 'Docker Desktop is running, but the Docker command could not be found. Open Docker Desktop from the Start menu and try again.'
        }
        $composeArgs = 'compose -f docker-compose.yml -f docker-compose.prod.yml up -d'
        $composeExit = Invoke-Native -FileName $docker -Arguments $composeArgs -WorkingDirectory $backend -TimeoutSeconds 180
        if ($composeExit -ne 0) {
            Show-Failure 'The clinic server did not start. Wait until Docker Desktop says it is running, then open Nabi Dental Clinic again.'
        }
        $deadline = (Get-Date).AddSeconds($serverWaitSeconds)
        $serverReady = $false
        while ((Get-Date) -lt $deadline) {
            if (Test-ClinicReady) {
                $serverReady = $true
                break
            }
            Set-Status 'Waiting for the clinic server...'
            Start-Sleep -Seconds 2
        }
        if (-not $serverReady) {
            Show-Failure 'The clinic server is still starting. Wait a minute, then open Nabi Dental Clinic again.'
        }
    }
    else {
        Write-Log 'Clinic server already ready; containers left running'
    }

    Show-ClinicWindow
    if ($form -and -not $form.IsDisposed) {
        $form.Close()
    }
    if ($unattended) {
        Set-Content -Path (Join-Path $logDir 'launch-result.txt') -Value 'ready'
    }
    exit 0
}
catch {
    Show-Failure 'Nabi Dental Clinic could not start. Wait a moment and try the desktop icon again.'
}
finally {
    if ($ownsMutex) {
        $mutex.ReleaseMutex() | Out-Null
    }
    $mutex.Dispose()
}
