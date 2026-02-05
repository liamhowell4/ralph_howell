#Requires -Version 5.1
<#
.SYNOPSIS
    Ralph Howell Loop - Autonomous development loop for Claude Code
.DESCRIPTION
    Main entry point for Ralph Howell Loop. Manages autonomous development
    iterations with task tracking, rate limiting, and circuit breakers.
.PARAMETER FromMd
    Transform a markdown PRD file before starting
.PARAMETER FromJson
    Use an existing prd.json file
.PARAMETER PrdPath
    Path to the PRD file (markdown or JSON)
.PARAMETER Resume
    Resume a paused session
.PARAMETER Reinit
    Force reinitialize, overwriting existing .ralph directory
.PARAMETER MaxIterations
    Override max iterations from config
.PARAMETER Engine
    Override the AI engine to use ("claude", "codex", or "opencode"). Default is from config.
.PARAMETER Codex
    Shorthand for -Engine codex. Use OpenAI Codex CLI instead of Claude.
.PARAMETER OpenCode
    Shorthand for -Engine opencode. Use OpenCode CLI instead of Claude.
.PARAMETER DryRun
    Preview what would happen without executing
.EXAMPLE
    .\ralph.ps1
    Interactive mode - prompts for configuration
.EXAMPLE
    .\ralph.ps1 -FromMd -PrdPath ".\PROMPT.md"
    Transform markdown PRD and start loop
.EXAMPLE
    .\ralph.ps1 -FromMd -PrdPath ".\PROMPT.md" -Codex
    Transform markdown PRD and start loop using Codex engine
.EXAMPLE
    .\ralph.ps1 -FromMd -PrdPath ".\PROMPT.md" -OpenCode
    Transform markdown PRD and start loop using OpenCode
.EXAMPLE
    .\ralph.ps1 -Resume -Codex
    Resume a paused session using Codex
.EXAMPLE
    .\ralph.ps1 -Resume
    Resume a paused session
#>

[CmdletBinding()]
param(
    [switch]$FromMd,
    [switch]$FromJson,
    [string]$PrdPath,
    [switch]$Resume,
    [switch]$Reinit,
    [int]$MaxIterations,
    [ValidateSet("claude", "codex", "opencode")]
    [string]$Engine,
    [switch]$Codex,
    [switch]$OpenCode,
    [switch]$DryRun
)

# Get script directory and load utils
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "utils.ps1")

# Handle engine shorthand flags
if ($Codex) {
    $Engine = "codex"
} elseif ($OpenCode) {
    $Engine = "opencode"
}

# ============================================================================
# GLOBAL STATE
# ============================================================================

$script:MonitorProcess = $null
$script:ApiProcess = $null
$script:ProjectPath = (Get-Location).Path

# ============================================================================
# CLEANUP HANDLER
# ============================================================================

function Stop-RalphProcesses {
    Write-RalphLog "Stopping Ralph processes..." -Level "INFO"

    if ($script:ApiProcess -and -not $script:ApiProcess.HasExited) {
        try {
            $script:ApiProcess.Kill()
            Write-RalphLog "Stopped project API server" -Level "DEBUG"
        } catch {
            Write-RalphLog "Failed to stop API process: $_" -Level "WARN"
        }
    }

    # Update state to paused and accumulate active runtime
    $state = Get-RalphState
    if ($state) {
        $sessionMinutes = 0
        if ($state.startTime) {
            $startTime = [datetime]$state.startTime
            $sessionMinutes = ((Get-Date) - $startTime).TotalMinutes
        }
        $previousMinutes = if ($state.totalActiveMinutes) { $state.totalActiveMinutes } else { 0 }

        Update-RalphState -Updates @{
            status = "paused"
            iterationStatus = "interrupted"
            totalActiveMinutes = $previousMinutes + $sessionMinutes
        }
    }
}

# Register cleanup on Ctrl+C
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Stop-RalphProcesses
} -ErrorAction SilentlyContinue

trap {
    Stop-RalphProcesses
    break
}

# ============================================================================
# INTERACTIVE FLOW
# ============================================================================

function Show-InteractiveMenu {
    <#
    .SYNOPSIS
        Shows interactive menu and returns configuration
    #>

    $result = @{
        Action = $null
        PrdPath = $null
        PrdType = $null
    }

    if (Test-RalphExists) {
        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host " Existing Ralph configuration found" -ForegroundColor Cyan
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host ""

        $state = Get-RalphState
        if ($state) {
            Write-Host "  Status: $($state.status)" -ForegroundColor Yellow
            Write-Host "  Iteration: $($state.currentIteration)" -ForegroundColor Yellow
            Write-Host "  Last update: $($state.lastUpdateTime)" -ForegroundColor Yellow
        }
        Write-Host ""

        $response = Read-Host "Resume existing loop? (Y/N)"
        if ($response -match '^[Yy]') {
            $result.Action = "resume"
            return $result
        }

        $response = Read-Host "Reinitialize from scratch? This will overwrite existing state. (Y/N)"
        if ($response -match '^[Yy]') {
            $result.Action = "reinit"
        } else {
            Write-Host "Exiting." -ForegroundColor Yellow
            return $null
        }
    } else {
        $result.Action = "new"
    }

    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host " Ralph Howell Loop Setup" -ForegroundColor Cyan
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host ""

    $response = Read-Host "Do you have a PROMPT.md file to transform? (Y/N)"
    if ($response -match '^[Yy]') {
        $defaultPath = ".\PROMPT.md"
        $path = Read-Host "Enter path [$defaultPath]"
        if ([string]::IsNullOrWhiteSpace($path)) {
            $path = $defaultPath
        }

        if (-not (Test-Path $path)) {
            Write-Host "File not found: $path" -ForegroundColor Red
            return $null
        }

        $result.PrdPath = $path
        $result.PrdType = "markdown"
        return $result
    }

    $response = Read-Host "Do you have an existing prd.json file? (Y/N)"
    if ($response -match '^[Yy]') {
        $path = Read-Host "Enter path"
        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-Host "Path required." -ForegroundColor Red
            return $null
        }

        if (-not (Test-Path $path)) {
            Write-Host "File not found: $path" -ForegroundColor Red
            return $null
        }

        $result.PrdPath = $path
        $result.PrdType = "json"
        return $result
    }

    Write-Host ""
    Write-Host "Cannot proceed without a PRD. Exiting." -ForegroundColor Red
    return $null
}

# ============================================================================
# DASHBOARD MANAGEMENT
# ============================================================================

function Start-MonitorDashboard {
    <#
    .SYNOPSIS
        Starts the monitor dashboard server if not running
    #>

    $monitorPort = 3500

    # Check if already running
    $portInUse = Test-PortInUse -Port $monitorPort
    Write-RalphLog "Port $monitorPort in use: $portInUse" -Level "DEBUG"

    if ($portInUse) {
        $isHealthy = Test-ApiHealth -Port $monitorPort
        Write-RalphLog "Health check result: $isHealthy" -Level "DEBUG"

        if ($isHealthy) {
            Write-RalphLog "Monitor dashboard already running on port $monitorPort" -Level "INFO"
            return $true
        } else {
            # Port in use but unhealthy - kill the zombie process
            Write-RalphLog "Found unhealthy process on port $monitorPort, cleaning up..." -Level "INFO"
            try {
                $conn = Get-NetTCPConnection -LocalPort $monitorPort -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($conn) {
                    Write-RalphLog "Killing process $($conn.OwningProcess) on port $monitorPort" -Level "INFO"
                    Stop-Process -Id $conn.OwningProcess -Force -ErrorAction Stop
                    Start-Sleep -Seconds 1
                    Write-RalphLog "Process killed successfully" -Level "DEBUG"
                } else {
                    Write-RalphLog "Could not find process holding port $monitorPort" -Level "WARN"
                }
            } catch {
                Write-RalphLog "Failed to cleanup stale process: $_" -Level "ERROR"
            }
        }
    }

    $dashboardDir = Join-Path (Split-Path $ScriptDir -Parent) "dashboard"

    if (-not (Test-Path (Join-Path $dashboardDir "server\index.js"))) {
        Write-RalphLog "Monitor server not found. Dashboard disabled." -Level "WARN"
        return $false
    }

    try {
        $serverPath = Join-Path $dashboardDir "server\index.js"

        # Check if monitor already running before starting
        if (Test-ApiHealth -Port $monitorPort) {
            Write-RalphLog "Monitor dashboard already running on port $monitorPort" -Level "INFO"
            return $true
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "node"
        $psi.Arguments = "`"$serverPath`""
        $psi.WorkingDirectory = $dashboardDir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        # Don't redirect streams - buffer overflow can kill the process on Windows
        $psi.RedirectStandardOutput = $false
        $psi.RedirectStandardError = $false

        $script:MonitorProcess = [System.Diagnostics.Process]::Start($psi)
        Write-RalphLog "Started monitor process (PID: $($script:MonitorProcess.Id))" -Level "DEBUG"

        # Wait for server to start
        Start-Sleep -Seconds 3

        # Check if process is still running
        if ($script:MonitorProcess.HasExited) {
            # Check if it failed because monitor is already running (EADDRINUSE)
            if (Test-ApiHealth -Port $monitorPort) {
                Write-RalphLog "Monitor dashboard already running on port $monitorPort (detected via EADDRINUSE)" -Level "INFO"
                return $true
            }

            Write-RalphLog "Monitor process exited early. Exit code: $($script:MonitorProcess.ExitCode)" -Level "ERROR"
            return $false
        }

        if (Test-ApiHealth -Port $monitorPort) {
            Write-RalphLog "Monitor dashboard started on port $monitorPort" -Level "INFO"
            return $true
        } else {
            Write-RalphLog "Monitor dashboard failed health check on port $monitorPort" -Level "WARN"
            return $false
        }
    } catch {
        Write-RalphLog "Failed to start monitor dashboard: $_" -Level "ERROR"
        return $false
    }
}

function Start-ProjectApi {
    <#
    .SYNOPSIS
        Starts the per-project API server
    #>

    $dashboardDir = Join-Path (Split-Path $ScriptDir -Parent) "dashboard"
    $apiPath = Join-Path $dashboardDir "server\project-api.js"

    if (-not (Test-Path $apiPath)) {
        Write-RalphLog "Project API server not found. API disabled." -Level "WARN"
        return $null
    }

    $port = Find-AvailablePort -StartPort 4001

    if (-not $port) {
        Write-RalphLog "No available port for project API" -Level "ERROR"
        return $null
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "node"
        $psi.Arguments = "`"$apiPath`" `"$script:ProjectPath`" $port"
        $psi.WorkingDirectory = $dashboardDir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        # Don't redirect streams - buffer overflow can kill the process on Windows
        $psi.RedirectStandardOutput = $false
        $psi.RedirectStandardError = $false

        $script:ApiProcess = [System.Diagnostics.Process]::Start($psi)
        Write-RalphLog "Started project API process (PID: $($script:ApiProcess.Id)) on port $port" -Level "DEBUG"

        # Wait for server to start with retry loop
        $maxRetries = 5
        $retryDelay = 2
        $healthy = $false

        for ($i = 1; $i -le $maxRetries; $i++) {
            Start-Sleep -Seconds $retryDelay

            # Check if process died
            if ($script:ApiProcess.HasExited) {
                Write-RalphLog "Project API exited early. Exit code: $($script:ApiProcess.ExitCode)" -Level "ERROR"
                return $null
            }

            # Try health check
            if (Test-ApiHealth -Port $port) {
                $healthy = $true
                break
            }

            Write-RalphLog "Health check attempt $i/$maxRetries failed, retrying..." -Level "DEBUG"
        }

        if ($healthy) {
            Write-RalphLog "Project API started on port $port" -Level "INFO"

            # Update state with port
            Update-RalphState -Updates @{ apiPort = $port }

            # Register with monitor
            Register-ProjectWithMonitor -Port $port

            return $port
        } else {
            Write-RalphLog "Project API failed health check on port $port after $maxRetries attempts" -Level "WARN"
            # Kill the process since it's not responding
            if (-not $script:ApiProcess.HasExited) {
                $script:ApiProcess.Kill()
            }
            return $null
        }
    } catch {
        Write-RalphLog "Failed to start project API: $_" -Level "ERROR"
        return $null
    }
}

function Register-ProjectWithMonitor {
    <#
    .SYNOPSIS
        Registers this project with the monitor dashboard
    #>
    param(
        [int]$Port
    )

    try {
        $body = @{
            name = (Split-Path $script:ProjectPath -Leaf)
            path = $script:ProjectPath
            port = $Port
        } | ConvertTo-Json

        Invoke-RestMethod -Uri "http://localhost:3500/api/projects" -Method POST -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue | Out-Null
        Write-RalphLog "Registered with monitor dashboard" -Level "DEBUG"
    } catch {
        Write-RalphLog "Failed to register with monitor: $_" -Level "DEBUG"
    }
}

# ============================================================================
# MAIN LOOP
# ============================================================================

function Start-RalphLoop {
    <#
    .SYNOPSIS
        Main development loop
    #>
    [CmdletBinding()]
    param(
        [int]$OverrideMaxIterations,

        [ValidateSet("claude", "codex")]
        [string]$OverrideEngine
    )

    $config = Get-RalphConfig
    $maxIter = if ($OverrideMaxIterations -gt 0) { $OverrideMaxIterations } else { $config.maxIterations }
    $engineToUse = if ($OverrideEngine) { $OverrideEngine } else { $config.engine }

    # Clear any existing stop signal
    Clear-StopSignal

    # Update state to running
    Update-RalphState -Updates @{
        status = "running"
    }

    $state = Get-RalphState
    $startIteration = if ($state.currentIteration) { $state.currentIteration } else { 0 }

    Write-RalphLog "Starting Ralph loop from iteration $startIteration (max: $maxIter, engine: $engineToUse)" -Level "INFO"

    for ($iteration = $startIteration; $iteration -lt $maxIter; $iteration++) {
        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host " Iteration $($iteration + 1) / $maxIter" -ForegroundColor Cyan
        Write-Host "=======================================" -ForegroundColor Cyan

        # Check stop signal
        if (Test-StopSignal) {
            Write-RalphLog "Stop signal detected. Pausing..." -Level "INFO"
            Update-RalphState -Updates @{
                status = "paused"
                iterationStatus = "interrupted"
                currentIteration = $iteration
            }
            return "stopped"
        }

        # Check circuit breaker
        $cbCheck = Test-CircuitBreaker
        if ($cbCheck.Triggered) {
            Write-RalphLog "Circuit breaker triggered: $($cbCheck.Reason)" -Level "WARN"
            Update-RalphState -Updates @{
                status = "circuit_breaker"
            }
            return "circuit_breaker"
        }

        # Refresh config each iteration (allows dashboard edits)
        $config = Get-RalphConfig

        # Get current task
        $prd = Get-RalphPrd
        if (-not $prd -or -not $prd.tasks) {
            Write-RalphLog "No PRD or tasks found" -Level "ERROR"
            return "error"
        }

        $pendingTasks = @($prd.tasks | Where-Object { $_.status -eq "pending" -or $_.status -eq "in_progress" })

        if ($pendingTasks.Count -eq 0) {
            Write-RalphLog "All tasks completed!" -Level "INFO"
            Update-RalphState -Updates @{
                status = "completed"
            }
            return "completed"
        }

        # Use dependency-aware task selection
        $currentTask = Get-NextAvailableTask -Prd $prd

        if (-not $currentTask) {
            # All remaining tasks are blocked by unmet dependencies
            Write-RalphLog "All remaining tasks blocked by unmet dependencies" -Level "WARN"
            Update-RalphState -Updates @{
                status = "dependency_blocked"
                currentIteration = $iteration
            }
            return "dependency_blocked"
        }
        Write-RalphLog "Working on task $($currentTask.id): $($currentTask.title)" -Level "INFO"

        # Check if this task has exceeded timeout retries
        $taskTimeoutCheck = Test-TaskTimeoutCircuitBreaker -TaskId $currentTask.id
        if ($taskTimeoutCheck.Triggered) {
            Write-RalphLog "Task timeout circuit breaker: $($taskTimeoutCheck.Reason)" -Level "WARN"
            Update-TaskStatus -TaskId $currentTask.id -Status "blocked"
            Update-RalphState -Updates @{
                status = "circuit_breaker"
            }
            return "circuit_breaker"
        }

        # Calculate effective timeout (may be extended if task previously timed out)
        $timeoutInfo = Get-EffectiveTimeout -TaskId $currentTask.id
        if ($timeoutInfo.ExtensionCount -gt 0) {
            Write-RalphLog "Task has timed out $($timeoutInfo.PreviousTimeouts) time(s), extending timeout to $($timeoutInfo.TimeoutMinutes)m (+$($timeoutInfo.ExtensionCount * $config.circuitBreaker.timeoutExtensionMinutes)m)" -Level "INFO"
        }

        # Mark task as in progress
        Update-TaskStatus -TaskId $currentTask.id -Status "in_progress"

        # Get git state before
        $changesBefore = Get-GitChanges

        # Build prompt for Claude
        $prompt = Build-IterationPrompt -Task $currentTask -Prd $prd -Iteration $iteration

        # Log conversation entry before invoking
        $conversationId = Add-ConversationEntry `
            -Iteration $iteration `
            -TaskId $currentTask.id `
            -TaskTitle $currentTask.title `
            -Prompt $prompt `
            -Status "running"

        # Invoke the configured engine (Claude or Codex) with effective timeout
        $result = Invoke-Engine `
            -Prompt $prompt `
            -Engine $engineToUse `
            -Model $config.model `
            -MaxTurns $config.maxTurnsPerIteration `
            -TimeoutMinutes $timeoutInfo.TimeoutMinutes `
            -Iteration $iteration `
            -TaskId $currentTask.id `
            -TaskTitle $currentTask.title

        if (-not $result.Success) {
            Write-RalphLog "Engine invocation failed: $($result.Error)" -Level "ERROR"

            # Update conversation with error
            if ($conversationId) {
                Update-ConversationEntry -EntryId $conversationId -Status "error" -Error $result.Error
            }

            # Track timeout for task-specific circuit breaker
            if ($result.TimedOut) {
                $newTimeoutCount = Add-TaskTimeout -TaskId $currentTask.id
                $maxTimeouts = if ($config.circuitBreaker.maxTaskTimeouts) { $config.circuitBreaker.maxTaskTimeouts } else { 3 }
                $remainingRetries = $maxTimeouts - $newTimeoutCount
                if ($remainingRetries -gt 0) {
                    $nextExtension = $config.circuitBreaker.timeoutExtensionMinutes
                    Write-RalphLog "Task timed out ($newTimeoutCount/$maxTimeouts). Will retry with +${nextExtension}m timeout ($remainingRetries retries remaining)" -Level "WARN"
                } else {
                    Write-RalphLog "Task reached maximum timeouts ($newTimeoutCount/$maxTimeouts). Will trigger circuit breaker on next attempt." -Level "WARN"
                }
            }

            # Track error for circuit breaker
            $state = Get-RalphState
            $lastError = if ($state.lastError) { $state.lastError } else { "" }
            $sameError = $result.Error -eq $lastError

            Update-RalphState -Updates @{
                currentIteration = $iteration
                lastError = $result.Error
                sameErrorCount = if ($sameError -and $state.sameErrorCount) { $state.sameErrorCount + 1 } else { 1 }
                errors = @($state.errors) + @($result.Error)
            }

            continue
        }

        # Parse Claude's response
        $signal = Find-CompletionSignal -Output $result.Output

        if ($signal -eq "COMPLETE") {
            Write-RalphLog "Task $($currentTask.id) marked COMPLETE" -Level "INFO"
            Update-TaskStatus -TaskId $currentTask.id -Status "completed"
        } elseif ($signal -eq "BLOCKED") {
            $blocker = Find-BlockerReason -Output $result.Output
            Write-RalphLog "Task $($currentTask.id) BLOCKED: $blocker" -Level "WARN"
            Update-TaskStatus -TaskId $currentTask.id -Status "blocked"
        }

        # Update conversation with response
        if ($conversationId) {
            $convStatus = if ($signal -eq "COMPLETE") { "completed" } elseif ($signal -eq "BLOCKED") { "blocked" } else { "completed" }
            Update-ConversationEntry `
                -EntryId $conversationId `
                -Response $result.Output `
                -Status $convStatus `
                -ElapsedMinutes $result.ElapsedMinutes
        }

        # Check for changes
        $changesAfter = Get-GitChanges
        $hasChanges = $changesAfter.Count -ne $changesBefore.Count

        # Reset noChangeCount if task completed OR if there are git changes
        # This prevents circuit breaker from triggering when tasks complete without code changes
        if ($hasChanges -or $signal -eq "COMPLETE") {
            Update-RalphState -Updates @{
                noChangeCount = 0
                filesChanged = @($changesAfter | ForEach-Object { $_.Path })
            }

            # Auto-commit if enabled and there are changes
            if ($hasChanges -and $config.git.autoCommit) {
                $commitMsg = "$($config.git.commitMessagePrefix) $($iteration + 1): $($currentTask.title)"
                New-GitCommit -Message $commitMsg
            }
        } else {
            $state = Get-RalphState
            $noChangeCount = if ($state.noChangeCount) { $state.noChangeCount + 1 } else { 1 }
            Update-RalphState -Updates @{
                noChangeCount = $noChangeCount
            }
            Write-RalphLog "No changes in iteration (count: $noChangeCount)" -Level "DEBUG"
        }

        # Update iteration counter
        Update-RalphState -Updates @{
            currentIteration = $iteration + 1
            lastError = $null
            sameErrorCount = 0
        }

        # Cooldown between iterations
        Start-Sleep -Seconds $config.rateLimiting.cooldownSeconds
    }

    Write-RalphLog "Reached maximum iterations ($maxIter)" -Level "INFO"
    Update-RalphState -Updates @{
        status = "max_iterations"
    }
    return "max_iterations"
}

function Build-IterationPrompt {
    <#
    .SYNOPSIS
        Builds the prompt for a single iteration
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Task,

        [Parameter(Mandatory = $true)]
        $Prd,

        [Parameter(Mandatory = $true)]
        [int]$Iteration
    )

    $completedTasks = @($Prd.tasks | Where-Object { $_.status -eq "completed" }) | ForEach-Object { "- [$($_.id)] $($_.title)" }
    $completedList = if ($completedTasks.Count -gt 0) { $completedTasks -join "`n" } else { "None yet" }

    $acceptanceCriteria = if ($Task.acceptanceCriteria) {
        ($Task.acceptanceCriteria | ForEach-Object { "- $_" }) -join "`n"
    } else {
        "No specific criteria defined"
    }

    # Build dependency context
    $dependencyContext = ""
    if ($Task.dependencies -and $Task.dependencies.Count -gt 0) {
        # Get completed dependencies for this task
        $completedDeps = @()
        foreach ($depId in $Task.dependencies) {
            $depTask = $Prd.tasks | Where-Object { $_.id -eq $depId }
            if ($depTask -and $depTask.status -eq "completed") {
                $completedDeps += "- [$($depTask.id)] $($depTask.title)"
            }
        }
        if ($completedDeps.Count -gt 0) {
            $dependencyContext = @"

## Completed Dependencies
The following prerequisite tasks have been completed:
$($completedDeps -join "`n")
"@
        }
    }

    # Find tasks that depend on current task (blocked by this one)
    $blockedByThis = ""
    $dependentTasks = @()
    foreach ($t in $Prd.tasks) {
        if ($t.dependencies -and $t.dependencies -contains $Task.id) {
            if ($t.status -eq "pending") {
                $dependentTasks += "- [$($t.id)] $($t.title)"
            }
        }
    }
    if ($dependentTasks.Count -gt 0) {
        $blockedByThis = @"

## Tasks Waiting on This
The following tasks are waiting for this task to complete:
$($dependentTasks -join "`n")
"@
    }

    $lines = @(
        "# Ralph Howell Loop - Iteration $($Iteration + 1)"
        ""
        "## Project: $($Prd.projectName)"
        "$($Prd.description)"
        ""
        "## Current Task"
        "**Task $($Task.id):** $($Task.title)"
        ""
        "**Description:**"
        "$($Task.description)"
        ""
        "**Acceptance Criteria:**"
        "$acceptanceCriteria"
        "$dependencyContext"
        "$blockedByThis"
        ""
        "## Completed Tasks"
        "$completedList"
        ""
        "## Instructions"
        ""
        "You are working autonomously in a development loop. Complete the current task by:"
        "1. Understanding what needs to be done"
        "2. Implementing the necessary changes"
        "3. Verifying your implementation meets the acceptance criteria"
        ""
        "When you have completed the task OR cannot proceed, you MUST include one of these signals at the end of your response:"
        ""
        "- If task is COMPLETE: <PROMISE>COMPLETE</PROMISE>"
        "- If task is BLOCKED (needs human input, external dependency, etc): <PROMISE>BLOCKED</PROMISE>"
        ""
        "If blocked, also explain the blocker:"
        "<BLOCKER>Reason why the task cannot proceed</BLOCKER>"
        ""
        "## Important Notes"
        "- Make focused, incremental changes"
        "- Test your changes when possible"
        "- If something is unclear, mark as BLOCKED rather than guessing"
        ""
        "## CRITICAL: Directory Boundary"
        "Your working directory is: $($script:ProjectPath)"
        "You MUST only create, edit, or delete files within this directory and its subdirectories."
        "You are STRICTLY FORBIDDEN from creating, editing, deleting, or writing to ANY file or directory outside of $($script:ProjectPath)."
        "This includes but is not limited to: parent directories, sibling directories, home directories, temp directories, and system paths."
        "If a task requires changes outside this directory, mark it as BLOCKED and explain why."
        ""
        "Begin working on Task $($Task.id): $($Task.title)"
    )

    return ($lines -join "`n")
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

function Main {
    Write-Host ""
    Write-Host "  +-------------------------------------+" -ForegroundColor Magenta
    Write-Host "  |     Ralph Howell Loop v1.0          |" -ForegroundColor Magenta
    Write-Host "  |     Autonomous Development Loop     |" -ForegroundColor Magenta
    Write-Host "  +-------------------------------------+" -ForegroundColor Magenta
    Write-Host ""

    # Determine action based on flags or interactive
    $action = $null
    $prdPath = $PrdPath
    $prdType = $null

    if ($Resume) {
        $action = "resume"
    } elseif ($Reinit) {
        $action = "reinit"
    } elseif ($FromMd) {
        $action = "new"
        $prdType = "markdown"
        if (-not $prdPath) { $prdPath = ".\PROMPT.md" }
    } elseif ($FromJson) {
        $action = "new"
        $prdType = "json"
    } else {
        # Interactive mode
        $menuResult = Show-InteractiveMenu
        if (-not $menuResult) {
            return
        }
        $action = $menuResult.Action
        $prdPath = $menuResult.PrdPath
        $prdType = $menuResult.PrdType
    }

    # Handle reinit
    if ($action -eq "reinit") {
        Initialize-RalphDirectory -Force
        # Continue to setup PRD interactively if not provided
        if (-not $prdPath -and -not $prdType) {
            $menuResult = Show-InteractiveMenu
            if (-not $menuResult) { return }
            $prdPath = $menuResult.PrdPath
            $prdType = $menuResult.PrdType
        }
    }

    # Handle new setup
    if ($action -eq "new" -or $action -eq "reinit") {
        # Always ensure .ralph directory and files exist (safe to call multiple times)
        Initialize-RalphDirectory

        if ($prdType -eq "markdown") {
            Write-RalphLog "Transforming markdown PRD: $prdPath" -Level "INFO"

            if ($DryRun) {
                Write-Host "[DRY RUN] Would transform: $prdPath" -ForegroundColor Yellow
                return
            }

            $prd = ConvertFrom-MarkdownPrd -MarkdownPath $prdPath -Engine $Engine
            if (-not $prd) {
                Write-RalphLog "Failed to transform PRD" -Level "ERROR"
                return
            }
            Save-RalphPrd -Prd $prd
        } elseif ($prdType -eq "json") {
            Write-RalphLog "Loading JSON PRD: $prdPath" -Level "INFO"

            if ($DryRun) {
                Write-Host "[DRY RUN] Would load: $prdPath" -ForegroundColor Yellow
                return
            }

            $prd = Get-Content -Path $prdPath -Raw | ConvertFrom-Json
            Save-RalphPrd -Prd $prd
        }

        # Initialize git if enabled
        $config = Get-RalphConfig
        if ($config.git.autoInit) {
            Initialize-GitRepo
        }
    }

    # Handle resume
    if ($action -eq "resume") {
        if (-not (Test-RalphExists)) {
            Write-RalphLog "No .ralph directory found. Cannot resume." -Level "ERROR"
            return
        }

        $state = Get-RalphState
        Write-RalphLog "Resuming from iteration $($state.currentIteration)" -Level "INFO"

        # Reset startTime for this session (totalActiveMinutes preserves previous runtime)
        Update-RalphState -Updates @{
            startTime = (Get-Date).ToString("o")
        }

        Clear-StopSignal
    }

    # Dry run check
    if ($DryRun) {
        Write-Host ""
        Write-Host "[DRY RUN] Configuration:" -ForegroundColor Yellow
        Write-Host "  Action: $action" -ForegroundColor Yellow
        Write-Host "  PRD Path: $prdPath" -ForegroundColor Yellow
        Write-Host "  PRD Type: $prdType" -ForegroundColor Yellow

        $config = Get-RalphConfig
        $engineToShow = if ($Engine) { $Engine } else { $config.engine }
        Write-Host "  Engine: $engineToShow" -ForegroundColor Yellow
        Write-Host "  Model: $($config.model)" -ForegroundColor Yellow
        Write-Host "  Max Iterations: $($config.maxIterations)" -ForegroundColor Yellow

        if (Test-RalphExists) {
            $prd = Get-RalphPrd
            if ($prd) {
                Write-Host "  Tasks: $($prd.tasks.Count)" -ForegroundColor Yellow
            }
        }
        return
    }

    # Start dashboard if enabled
    $config = Get-RalphConfig
    if ($config.dashboard.enabled) {
        Start-MonitorDashboard | Out-Null
        Start-ProjectApi | Out-Null
    }

    # Run the main loop
    try {
        $loopParams = @{}
        if ($MaxIterations -gt 0) { $loopParams['OverrideMaxIterations'] = $MaxIterations }
        if ($Engine) { $loopParams['OverrideEngine'] = $Engine }
        $result = Start-RalphLoop @loopParams

        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host " Loop finished: $result" -ForegroundColor Cyan
        Write-Host "=======================================" -ForegroundColor Cyan
    } finally {
        Stop-RalphProcesses
    }
}

# Run main
Main
