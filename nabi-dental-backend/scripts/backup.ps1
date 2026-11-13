param(
    [string]$OutputDir = $(Join-Path ([Environment]::GetFolderPath("MyDocuments")) "NabiDentalBackups")
)

$ErrorActionPreference = "Stop"
$ComposeDir = Split-Path -Parent $PSScriptRoot
Set-Location $ComposeDir

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$stamp = Get-Date -Format "yyyy-MM-dd-HHmm"
$work = Join-Path $env:TEMP "nabi-backup-$stamp"
New-Item -ItemType Directory -Force -Path $work | Out-Null

try {
    docker compose exec -T db pg_dump -U postgres -Fc --no-owner --no-acl -f /tmp/nabi.dump nabi_dental
    docker compose cp db:/tmp/nabi.dump (Join-Path $work "database.dump")
    docker compose exec -T db rm -f /tmp/nabi.dump
    $dumpFile = Get-Item (Join-Path $work "database.dump")
    if ($dumpFile.Length -eq 0) {
        throw "Database dump was empty. Start Docker from nabi-dental-backend and try again."
    }

    $uploads = Join-Path $work "uploads"
    New-Item -ItemType Directory -Force -Path $uploads | Out-Null
    docker compose cp app:/app/uploads/. $uploads

    $manifest = @{
        kind             = "nabi-dental-backup"
        format_version   = 1
        created_at       = [DateTime]::UtcNow.ToString("o")
        app              = "Nabi Dental Clinic"
        includes_uploads = $true
    } | ConvertTo-Json
    Set-Content -Path (Join-Path $work "manifest.json") -Value $manifest -Encoding utf8

    $zipPath = Join-Path $OutputDir "nabi-dental-backup-$stamp.zip"
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($work, $zipPath)
    Write-Host "Backup saved: $zipPath"
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
