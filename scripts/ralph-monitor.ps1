#Requires -Version 5.1
<#
.SYNOPSIS
    Ralph Monitor Launcher - Manually start the dashboard
.DESCRIPTION
    Starts the monitor dashboard server and optionally opens the browser.
.PARAMETER NoBrowser
    Don't open browser automatically
.PARAMETER Port
    Override default port (3500)
.EXAMPLE
    .\ralph-monitor.ps1
    Start monitor and open browser
.EXAMPLE
    .\ralph-monitor.ps1 -NoBrowser
    Start monitor without opening browser
#>

[CmdletBinding()]
param(
    [switch]$NoBrowser,
    [int]$Port = 3500
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DashboardDir = Join-Path (Split-Path $ScriptDir -Parent) "dashboard"

Write-Host ""
Write-Host "  +-------------------------------------+" -ForegroundColor Magenta
Write-Host "  |     Ralph Monitor Dashboard         |" -ForegroundColor Magenta
Write-Host "  +-------------------------------------+" -ForegroundColor Magenta
Write-Host ""

# Check if already running
try {
    $response = Invoke-RestMethod -Uri "http://localhost:$Port/api/health" -TimeoutSec 2
    Write-Host "Monitor already running on port $Port" -ForegroundColor Yellow
    Write-Host "  Projects: $($response.projectCount)" -ForegroundColor Cyan
    Write-Host "  Uptime: $([math]::Round($response.uptime, 0)) seconds" -ForegroundColor Cyan

    if (-not $NoBrowser) {
        Start-Process "http://localhost:5173"
    }
    return
} catch {
    # Not running, continue to start
}

# Check for node_modules
$nodeModules = Join-Path $DashboardDir "node_modules"
if (-not (Test-Path $nodeModules)) {
    Write-Host "Installing dependencies..." -ForegroundColor Yellow
    Push-Location $DashboardDir
    try {
        npm install
    } finally {
        Pop-Location
    }
}

# Start monitor server
Write-Host "Starting monitor server on port $Port..." -ForegroundColor Cyan

$serverPath = Join-Path $DashboardDir "server\index.js"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "node"
$psi.Arguments = "`"$serverPath`""
$psi.WorkingDirectory = $DashboardDir
$psi.UseShellExecute = $false

$process = [System.Diagnostics.Process]::Start($psi)

# Wait for server to start
Start-Sleep -Seconds 2

# Verify it started
try {
    $response = Invoke-RestMethod -Uri "http://localhost:$Port/api/health" -TimeoutSec 2
    Write-Host "Monitor started successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  API: http://localhost:$Port" -ForegroundColor Cyan
    Write-Host "  Dashboard: http://localhost:5173 (run 'npm run dev' in dashboard/)" -ForegroundColor Cyan
    Write-Host ""

    if (-not $NoBrowser) {
        Write-Host "Starting Vite dev server..." -ForegroundColor Cyan
        Push-Location $DashboardDir
        try {
            Start-Process -FilePath "npm" -ArgumentList "run", "dev" -NoNewWindow
        } finally {
            Pop-Location
        }

        Start-Sleep -Seconds 3
        Start-Process "http://localhost:5173"
    }

    Write-Host "Press Ctrl+C to stop the monitor." -ForegroundColor Yellow
    Write-Host ""

    # Keep script running
    try {
        $process.WaitForExit()
    } catch {
        # Ignore Ctrl+C
    }
} catch {
    Write-Host "Failed to start monitor server" -ForegroundColor Red
    if ($process -and -not $process.HasExited) {
        $process.Kill()
    }
}
