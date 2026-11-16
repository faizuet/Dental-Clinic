# Starts the clinic database and API, then opens the release desktop app.
# Existing Docker volumes are reused. This script does not delete data.
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $repo 'nabi-dental-backend'
$appDir = Join-Path $repo 'dist\Nabi Dental Clinic'
$appExe = Join-Path $appDir 'nabi_dental_app.exe'
$logDir = Join-Path $env:LOCALAPPDATA 'NabiDental'
$logFile = Join-Path $logDir 'launch.log'

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Write-Log([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $logFile -Value $line
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Nabi Dental Clinic'
$form.ClientSize = New-Object System.Drawing.Size(440, 120)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ControlBox = $false
$form.TopMost = $true
$status = New-Object System.Windows.Forms.Label
$status.Name = 'status'
$status.Text = 'Starting Nabi Dental Clinic...'
$status.Font = New-Object System.Drawing.Font('Segoe UI', 12)
$status.Dock = 'Fill'
$status.TextAlign = 'MiddleLeft'
$status.Padding = New-Object System.Windows.Forms.Padding(24, 0, 24, 0)
$form.Controls.Add($status)
$form.Show()

function Set-Status([string]$Text) {
    $status.Text = $Text
    [System.Windows.Forms.Application]::DoEvents()
    Write-Log $Text
}

function Show-Failure([string]$Text) {
    Write-Log "FAILED $Text"
    if ($form -and -not $form.IsDisposed) {
        $form.Close()
    }
    [System.Windows.Forms.MessageBox]::Show($Text, 'Nabi Dental Clinic') | Out-Null
    exit 1
}

function Test-Docker {
    docker info *> $null
    return $LASTEXITCODE -eq 0
}

try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Show-Failure 'Docker Desktop is not installed, so the clinic database cannot start.'
    }
    if (-not (Test-Path $appExe)) {
        Show-Failure "The desktop app was not found at $appExe."
    }

    if (-not (Test-Docker)) {
        Set-Status 'Opening Docker Desktop...'
        $desktop = @(
            "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
            "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $desktop) {
            Show-Failure 'Docker Desktop is not running, and Docker Desktop.exe was not found.'
        }
        Start-Process -FilePath $desktop | Out-Null
        $engine = $false
        for ($i = 0; $i -lt 90; $i++) {
            if (Test-Docker) {
                $engine = $true
                break
            }
            Set-Status 'Waiting for Docker Desktop...'
            Start-Sleep -Seconds 2
        }
        if (-not $engine) {
            Show-Failure 'Docker Desktop did not become ready. Open it, wait until it says it is running, then try again.'
        }
    }

    Set-Status 'Starting the clinic database and server...'
    Push-Location $backend
    try {
        & docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
        if ($LASTEXITCODE -ne 0) {
            Show-Failure 'The clinic server did not start. Open Docker Desktop and try again.'
        }
    }
    finally {
        Pop-Location
    }

    $healthy = $false
    for ($i = 0; $i -lt 90; $i++) {
        try {
            $response = Invoke-WebRequest -Uri 'http://127.0.0.1:8001/health' -UseBasicParsing -TimeoutSec 3
            if ($response.StatusCode -eq 200) {
                $healthy = $true
                break
            }
        }
        catch {
            Set-Status 'Waiting for the clinic server...'
        }
        Start-Sleep -Seconds 1
    }
    if (-not $healthy) {
        Show-Failure 'The clinic server did not become ready. Wait a moment and open Nabi Dental again.'
    }

    $running = Get-Process -Name 'nabi_dental_app' -ErrorAction SilentlyContinue
    if (-not $running) {
        Set-Status 'Opening the clinic...'
        Start-Process -FilePath $appExe -WorkingDirectory $appDir | Out-Null
    }
    Write-Log 'Clinic window launched'
    $form.Close()
    exit 0
}
catch {
    Show-Failure $_.Exception.Message
}
