param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $ZipPath)) {
    throw "Backup zip not found: $ZipPath"
}

Write-Host "This replaces ALL clinic records and X-rays in Docker with the backup."
$confirm = Read-Host "Type RESTORE to continue"
if ($confirm -ne "RESTORE") {
    throw "Restore cancelled."
}

$ComposeDir = Split-Path -Parent $PSScriptRoot
Set-Location $ComposeDir

$work = Join-Path $env:TEMP ("nabi-restore-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path $ZipPath), $work)

    $manifestPath = Join-Path $work "manifest.json"
    $dumpPath = Join-Path $work "database.dump"
    if (-not (Test-Path $manifestPath) -or -not (Test-Path $dumpPath)) {
        throw "This zip is not a Nabi Dental clinic backup."
    }
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.kind -ne "nabi-dental-backup") {
        throw "This zip is not a Nabi Dental clinic backup."
    }

    # Same restore as Settings in the app: database, X-rays, and schema upgrade for older backups.
    docker compose cp (Resolve-Path $ZipPath) app:/tmp/nabi-restore.zip
    docker compose exec -T app python -m app.services.backup_service /tmp/nabi-restore.zip
    $restoreExit = $LASTEXITCODE
    docker compose exec -T app rm -f /tmp/nabi-restore.zip
    if ($restoreExit -ne 0) {
        throw "Restore failed. Keep Docker running and try again."
    }
    Write-Host "Restore finished. Open the desktop app and sign in if asked."
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
