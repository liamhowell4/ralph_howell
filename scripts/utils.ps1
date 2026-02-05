#Requires -Version 5.1
<#
.SYNOPSIS
    Shared utilities for Ralph Howell Loop
.DESCRIPTION
    Provides logging, state management, config, git operations, signal parsing, and port allocation.
    Compatible with PowerShell 5.1 and 7+
#>

# ============================================================================
# CONFIGURATION DEFAULTS
# ============================================================================

$script:DefaultConfig = @{
    engine = "claude"  # "claude" or "codex"
    model = "claude-opus-4-5-20251101"
    maxIterations = 50
    maxTurnsPerIteration = 50
    iterationTimeoutMinutes = 15  # Kill iterations that take longer than this
    rateLimiting = @{
        maxCallsPerHour = 100
        cooldownSeconds = 10
        retryCount = 1
    }
    circuitBreaker = @{
        maxNoChangeIterations = 3
        maxSameErrorIterations = 5
        maxTotalMinutes = 480
        maxTaskTimeouts = 3          # Max timeouts per task before circuit break (original + 2 extensions)
        timeoutExtensionMinutes = 5  # Additional minutes per retry after timeout
    }
    git = @{
        autoCommit = $true
        autoInit = $true
        commitMessagePrefix = "Ralph iteration"
    }
    dashboard = @{
        enabled = $true
    }
}

$script:RalphDir = ".ralph"
$script:StateFile = "state.json"
$script:ConfigFile = "config.json"
$script:PrdFile = "prd.json"
$script:LogFile = "ralph.log"
$script:TimestampsFile = "call_timestamps.json"
$script:StopSignalFile = "stop.signal"
$script:ConversationsFile = "conversations.json"

# ============================================================================
# LOGGING
# ============================================================================

function Write-RalphLog {
    <#
    .SYNOPSIS
        Writes a log entry to both console and log file
    .PARAMETER Message
        The message to log
    .PARAMETER Level
        Log level: DEBUG, INFO, WARN, ERROR
    .PARAMETER NoConsole
        Suppress console output
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Position = 1)]
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",

        [switch]$NoConsole
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Console output with colors
    if (-not $NoConsole) {
        $color = switch ($Level) {
            "DEBUG" { "Gray" }
            "INFO"  { "White" }
            "WARN"  { "Yellow" }
            "ERROR" { "Red" }
            default { "White" }
        }
        Write-Host $logEntry -ForegroundColor $color
    }

    # File output
    $ralphPath = Get-RalphPath
    if ($ralphPath) {
        $logPath = Join-Path $ralphPath $script:LogFile
        try {
            Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
        } catch {
            # Silently fail if can't write to log
        }
    }
}

function Get-RalphLogTail {
    <#
    .SYNOPSIS
        Gets the last N lines from the log file
    .PARAMETER Lines
        Number of lines to retrieve
    #>
    [CmdletBinding()]
    param(
        [int]$Lines = 100
    )

    $ralphPath = Get-RalphPath
    if (-not $ralphPath) { return @() }

    $logPath = Join-Path $ralphPath $script:LogFile
    if (-not (Test-Path $logPath)) { return @() }

    return Get-Content -Path $logPath -Tail $Lines
}

# ============================================================================
# PATH UTILITIES
# ============================================================================

function Get-RalphPath {
    <#
    .SYNOPSIS
        Gets the .ralph directory path for the current project
    .PARAMETER ProjectPath
        Optional project path, defaults to current directory
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    return Join-Path $ProjectPath $script:RalphDir
}

function Test-RalphExists {
    <#
    .SYNOPSIS
        Checks if .ralph directory exists
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    return Test-Path $ralphPath
}

function Initialize-RalphDirectory {
    <#
    .SYNOPSIS
        Creates and initializes the .ralph directory
    .PARAMETER ProjectPath
        Project path to initialize
    .PARAMETER Force
        Overwrite existing .ralph directory
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path,
        [switch]$Force
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath

    if ((Test-Path $ralphPath) -and $Force) {
        Remove-Item -Path $ralphPath -Recurse -Force
    }

    if (-not (Test-Path $ralphPath)) {
        New-Item -Path $ralphPath -ItemType Directory -Force | Out-Null
    }

    # Initialize config with defaults
    $configPath = Join-Path $ralphPath $script:ConfigFile
    if (-not (Test-Path $configPath)) {
        Save-RalphConfig -Config $script:DefaultConfig -ProjectPath $ProjectPath
    }

    # Initialize empty state
    $statePath = Join-Path $ralphPath $script:StateFile
    if (-not (Test-Path $statePath)) {
        $initialState = @{
            status = "initialized"
            currentIteration = 0
            currentTaskIndex = 0
            startTime = (Get-Date).ToString("o")
            lastUpdateTime = (Get-Date).ToString("o")
            totalActiveMinutes = 0  # Cumulative runtime excluding paused time
            apiPort = $null
            errors = @()
            noChangeCount = 0
            sameErrorCount = 0
            lastError = $null
            filesChanged = @()
            testResults = $null
            taskTimeouts = @{}  # Track timeout count per task (taskId -> count)
        }
        Save-RalphState -State $initialState -ProjectPath $ProjectPath
    }

    # Initialize empty timestamps
    $timestampsPath = Join-Path $ralphPath $script:TimestampsFile
    if (-not (Test-Path $timestampsPath)) {
        Save-CallTimestamps -Timestamps @() -ProjectPath $ProjectPath
    }

    # Create empty log file
    $logPath = Join-Path $ralphPath $script:LogFile
    if (-not (Test-Path $logPath)) {
        New-Item -Path $logPath -ItemType File -Force | Out-Null
    }

    Write-RalphLog "Initialized .ralph directory at $ralphPath" -Level "INFO"
    return $ralphPath
}

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

function Get-RalphState {
    <#
    .SYNOPSIS
        Reads the current state from state.json
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $statePath = Join-Path $ralphPath $script:StateFile

    if (-not (Test-Path $statePath)) {
        return $null
    }

    try {
        $content = Get-Content -Path $statePath -Raw
        return $content | ConvertFrom-Json
    } catch {
        Write-RalphLog "Failed to read state: $_" -Level "ERROR"
        return $null
    }
}

function Save-RalphState {
    <#
    .SYNOPSIS
        Saves state to state.json atomically
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [string]$ProjectPath = (Get-Location).Path
    )

    $State.lastUpdateTime = (Get-Date).ToString("o")

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $statePath = Join-Path $ralphPath $script:StateFile
    $tempPath = "$statePath.tmp"

    try {
        $json = $State | ConvertTo-Json -Depth 10
        Set-Content -Path $tempPath -Value $json -Force
        Move-Item -Path $tempPath -Destination $statePath -Force
    } catch {
        Write-RalphLog "Failed to save state: $_" -Level "ERROR"
        throw
    }
}

function Update-RalphState {
    <#
    .SYNOPSIS
        Updates specific properties in state.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Updates,

        [string]$ProjectPath = (Get-Location).Path
    )

    $state = Get-RalphState -ProjectPath $ProjectPath
    if (-not $state) {
        # State doesn't exist - initialize it first
        Write-RalphLog "State file missing, initializing..." -Level "DEBUG"
        Initialize-RalphDirectory -ProjectPath $ProjectPath
        $state = Get-RalphState -ProjectPath $ProjectPath
        if (-not $state) {
            Write-RalphLog "Failed to initialize state" -Level "ERROR"
            return
        }
    }

    # Convert PSCustomObject to hashtable for merging
    $stateHash = @{}
    $state.PSObject.Properties | ForEach-Object {
        $stateHash[$_.Name] = $_.Value
    }

    foreach ($key in $Updates.Keys) {
        $stateHash[$key] = $Updates[$key]
    }

    Save-RalphState -State $stateHash -ProjectPath $ProjectPath
}

# ============================================================================
# CONFIG MANAGEMENT
# ============================================================================

function Get-RalphConfig {
    <#
    .SYNOPSIS
        Reads config.json, merging with defaults
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $configPath = Join-Path $ralphPath $script:ConfigFile

    # Start with defaults
    $config = $script:DefaultConfig.Clone()

    if (Test-Path $configPath) {
        try {
            $content = Get-Content -Path $configPath -Raw
            $fileConfig = $content | ConvertFrom-Json

            # Merge file config over defaults
            $fileConfig.PSObject.Properties | ForEach-Object {
                $propName = $_.Name
                $propValue = $_.Value
                if ($propValue -is [PSCustomObject]) {
                    # Deep merge for nested objects
                    if (-not $config.ContainsKey($propName)) {
                        $config[$propName] = @{}
                    }
                    $propValue.PSObject.Properties | ForEach-Object {
                        $config[$propName][$_.Name] = $_.Value
                    }
                } else {
                    $config[$propName] = $propValue
                }
            }
        } catch {
            Write-RalphLog "Failed to read config, using defaults: $_" -Level "WARN"
        }
    }

    return $config
}

function Save-RalphConfig {
    <#
    .SYNOPSIS
        Saves config to config.json atomically
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $configPath = Join-Path $ralphPath $script:ConfigFile
    $tempPath = "$configPath.tmp"

    try {
        $json = $Config | ConvertTo-Json -Depth 10
        Set-Content -Path $tempPath -Value $json -Force
        Move-Item -Path $tempPath -Destination $configPath -Force
    } catch {
        Write-RalphLog "Failed to save config: $_" -Level "ERROR"
        throw
    }
}

# ============================================================================
# PRD MANAGEMENT
# ============================================================================

function Get-RalphPrd {
    <#
    .SYNOPSIS
        Reads prd.json
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $prdPath = Join-Path $ralphPath $script:PrdFile

    if (-not (Test-Path $prdPath)) {
        return $null
    }

    try {
        $content = Get-Content -Path $prdPath -Raw
        return $content | ConvertFrom-Json
    } catch {
        Write-RalphLog "Failed to read PRD: $_" -Level "ERROR"
        return $null
    }
}

function Save-RalphPrd {
    <#
    .SYNOPSIS
        Saves PRD to prd.json atomically
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Prd,

        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $prdPath = Join-Path $ralphPath $script:PrdFile
    $tempPath = "$prdPath.tmp"

    try {
        # Handle both hashtable and PSCustomObject
        if ($Prd -is [hashtable]) {
            $json = $Prd | ConvertTo-Json -Depth 20
        } else {
            $json = $Prd | ConvertTo-Json -Depth 20
        }
        Set-Content -Path $tempPath -Value $json -Force
        Move-Item -Path $tempPath -Destination $prdPath -Force
    } catch {
        Write-RalphLog "Failed to save PRD: $_" -Level "ERROR"
        throw
    }
}

function ConvertFrom-MarkdownPrd {
    <#
    .SYNOPSIS
        Transforms a markdown PRD into structured JSON format
    .PARAMETER MarkdownPath
        Path to the markdown file
    .PARAMETER Engine
        Override engine selection ("claude", "codex", or "opencode")
    .DESCRIPTION
        Uses the configured engine (Claude, Codex, or OpenCode) to transform a markdown PRD
        into the structured JSON format
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MarkdownPath,

        [ValidateSet("claude", "codex", "opencode")]
        [string]$Engine
    )

    if (-not (Test-Path $MarkdownPath)) {
        Write-RalphLog "Markdown file not found: $MarkdownPath" -Level "ERROR"
        return $null
    }

    $config = Get-RalphConfig
    $selectedEngine = if ($Engine) { $Engine } else { $config.engine }
    if (-not $selectedEngine) {
        $selectedEngine = "claude"
    }

    $mdContent = Get-Content -Path $MarkdownPath -Raw

    $transformPrompt = @"
You are a JSON generator. Your ONLY output must be valid JSON - no explanations, no markdown, no text before or after.

Convert this PRD to JSON with this structure:
{
  "projectName": "string",
  "description": "string",
  "tasks": [
    {
      "id": "1",
      "title": "string",
      "description": "string",
      "status": "pending",
      "acceptanceCriteria": ["string"],
      "dependencies": [],
      "subtasks": []
    }
  ],
  "dependencyGraph": {
    "nodes": ["1", "2", "3"],
    "edges": [{"from": "1", "to": "2"}]
  }
}

Rules:
- ALL task IDs must be strings (e.g. "1", "2", "7.1")
- Extract ALL tasks from the Task Checklist section
- Each top-level checkbox item becomes a task with sequential string IDs starting at "1"
- If a task has sub-items (indented checkboxes), create subtasks with decimal IDs (e.g. task "7" gets subtasks "7.1", "7.2", "7.3")
- Set all statuses to "pending"
- IMPORTANT: Parse task dependencies from the PRD content:
  - Look for patterns like "depends on task N", "after task N", "requires task N"
  - Look for bracket notation like [depends: 1, 3] or [after: 2]
  - Look for natural language like "once X is complete" or "after implementing Y"
  - Populate the "dependencies" array with task IDs that must complete first
- Build the dependencyGraph object:
  - "nodes" is an array of all task IDs
  - "edges" is an array of {from, to} where "from" is the dependency and "to" is the dependent task
- If no dependencies are found for a task, use an empty array []
- Output ONLY the JSON object, nothing else

PRD content:
$mdContent
"@

    Write-RalphLog "Transforming markdown PRD with $selectedEngine..." -Level "INFO"

    try {
        $jsonContent = Invoke-EngineSimple -Prompt $transformPrompt -Engine $selectedEngine

        # For Claude CLI with --output-format json: {"type":"result","result":"...content..."}
        # For Codex: JSONL format already parsed by Invoke-EngineSimple
        $cliResponse = $null
        try {
            $cliResponse = $jsonContent | ConvertFrom-Json
        } catch {
            Write-RalphLog "CLI response is not valid JSON, trying raw extraction" -Level "DEBUG"
        }

        $prdContent = $null
        if ($cliResponse -and $cliResponse.type -eq "result" -and $cliResponse.result) {
            # Extract the actual content from the CLI wrapper (Claude format)
            $prdContent = $cliResponse.result
            Write-RalphLog "Extracted result from CLI wrapper (length: $($prdContent.Length))" -Level "DEBUG"
        } else {
            # Use raw content
            $prdContent = $jsonContent
        }

        # Strip markdown code blocks if present (```json ... ```)
        if ($prdContent -match '(?s)```(?:json)?\s*(\{.+\})\s*```') {
            $prdContent = $Matches[1]
            Write-RalphLog "Extracted JSON from markdown code block" -Level "DEBUG"
        }
        # Extract JSON object if mixed with other text
        elseif ($prdContent -match '(?s)(\{"projectName".+\})') {
            $prdContent = $Matches[1]
            Write-RalphLog "Extracted JSON object from mixed content" -Level "DEBUG"
        }

        $prd = $prdContent | ConvertFrom-Json

        if (-not $prd.tasks -or $prd.tasks.Count -eq 0) {
            Write-RalphLog "PRD transformation produced no tasks" -Level "ERROR"
            return $null
        }

        Write-RalphLog "Transformed PRD: $($prd.tasks.Count) tasks extracted" -Level "INFO"

        # Validate dependencies
        $hasDependencies = $false
        foreach ($task in $prd.tasks) {
            if ($task.dependencies -and $task.dependencies.Count -gt 0) {
                $hasDependencies = $true
                break
            }
        }

        if ($hasDependencies) {
            Write-RalphLog "Validating task dependencies..." -Level "INFO"

            # Validate dependency references
            $validation = Test-DependencyValidation -Prd $prd
            if (-not $validation.Valid) {
                foreach ($error in $validation.Errors) {
                    Write-RalphLog "Dependency error: $error" -Level "ERROR"
                }
                Write-RalphLog "PRD transformation failed dependency validation" -Level "ERROR"
                return $null
            }

            # Check for circular dependencies
            $cycleCheck = Test-CircularDependencies -Prd $prd
            if ($cycleCheck.HasCycle) {
                $cyclePath = $cycleCheck.CyclePath -join " -> "
                Write-RalphLog "Circular dependency detected: $cyclePath" -Level "ERROR"
                return $null
            }

            Write-RalphLog "Dependency validation passed" -Level "INFO"
        }

        # Build dependency graph if not provided by LLM
        if (-not $prd.dependencyGraph) {
            $prd | Add-Member -NotePropertyName 'dependencyGraph' -NotePropertyValue (Build-DependencyGraph -Prd $prd) -Force
            Write-RalphLog "Built dependency graph" -Level "DEBUG"
        }

        # Add metadata
        if (-not $prd.metadata) {
            $prd | Add-Member -NotePropertyName 'metadata' -NotePropertyValue @{} -Force
        }
        $prd.metadata | Add-Member -NotePropertyName 'hasDependencies' -NotePropertyValue $hasDependencies -Force
        $prd.metadata | Add-Member -NotePropertyName 'validatedAt' -NotePropertyValue (Get-Date).ToString("o") -Force

        return $prd
    } catch {
        Write-RalphLog "Failed to transform markdown PRD: $_" -Level "ERROR"
        if ($prdContent) {
            Write-RalphLog "Content being parsed (first 300 chars): $($prdContent.Substring(0, [Math]::Min(300, $prdContent.Length)))" -Level "WARN"
        } elseif ($jsonContent) {
            Write-RalphLog "Raw CLI response (first 300 chars): $($jsonContent.Substring(0, [Math]::Min(300, $jsonContent.Length)))" -Level "WARN"
        }
        return $null
    }
}

# ============================================================================
# DEPENDENCY MANAGEMENT
# ============================================================================

function Test-DependencyValidation {
    <#
    .SYNOPSIS
        Validates that all dependency references are valid
    .PARAMETER Prd
        The PRD object with tasks
    .OUTPUTS
        Hashtable with:
        - Valid: boolean
        - Errors: array of error messages
    .DESCRIPTION
        Validates:
        1. All referenced task IDs exist
        2. Subtasks can only depend on siblings within the same parent
        3. No self-references
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Prd
    )

    $result = @{
        Valid = $true
        Errors = @()
    }

    if (-not $Prd.tasks) {
        return $result
    }

    # Build map of task IDs for quick lookup
    $taskIds = @{}
    $taskParents = @{}  # Track parent of each subtask

    foreach ($task in $Prd.tasks) {
        $taskIds[$task.id] = $task

        # Check for subtasks
        if ($task.subtasks) {
            foreach ($subtask in $task.subtasks) {
                $taskIds[$subtask.id] = $subtask
                $taskParents[$subtask.id] = $task.id
            }
        }
    }

    # Validate each task's dependencies
    foreach ($task in $Prd.tasks) {
        $tasksToCheck = @($task)
        if ($task.subtasks) {
            $tasksToCheck += $task.subtasks
        }

        foreach ($t in $tasksToCheck) {
            if (-not $t.dependencies) { continue }

            foreach ($depId in $t.dependencies) {
                # Check for self-reference
                if ($depId -eq $t.id) {
                    $result.Valid = $false
                    $result.Errors += "Task $($t.id) cannot depend on itself"
                    continue
                }

                # Check if referenced task exists
                if (-not $taskIds.ContainsKey($depId)) {
                    $result.Valid = $false
                    $result.Errors += "Task $($t.id) depends on non-existent task $depId"
                    continue
                }

                # Check subtask scoping: subtasks can only depend on siblings
                $taskParent = $taskParents[$t.id]
                $depParent = $taskParents[$depId]

                if ($taskParent -and $depParent) {
                    # Both are subtasks - must have same parent
                    if ($taskParent -ne $depParent) {
                        $result.Valid = $false
                        $result.Errors += "Subtask $($t.id) cannot depend on subtask $depId from different parent task"
                    }
                } elseif ($taskParent -and -not $depParent) {
                    # Subtask depending on top-level task is OK (can depend on parent or other top-level)
                } elseif (-not $taskParent -and $depParent) {
                    # Top-level task depending on subtask
                    $result.Valid = $false
                    $result.Errors += "Top-level task $($t.id) cannot depend on subtask $depId"
                }
            }
        }
    }

    return $result
}

function Test-CircularDependencies {
    <#
    .SYNOPSIS
        Detects circular dependencies using DFS
    .PARAMETER Prd
        The PRD object with tasks
    .OUTPUTS
        Hashtable with:
        - HasCycle: boolean
        - CyclePath: array showing the cycle (if found)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Prd
    )

    $result = @{
        HasCycle = $false
        CyclePath = @()
    }

    if (-not $Prd.tasks) {
        return $result
    }

    # Build adjacency list (task -> tasks it depends on)
    $dependencies = @{}

    foreach ($task in $Prd.tasks) {
        if ($task.dependencies) {
            $dependencies[$task.id] = @($task.dependencies)
        } else {
            $dependencies[$task.id] = @()
        }

        # Include subtasks
        if ($task.subtasks) {
            foreach ($subtask in $task.subtasks) {
                if ($subtask.dependencies) {
                    $dependencies[$subtask.id] = @($subtask.dependencies)
                } else {
                    $dependencies[$subtask.id] = @()
                }
            }
        }
    }

    # Iterative DFS cycle detection using explicit stack
    $visited = @{}
    $recursionStack = @{}

    foreach ($startTaskId in $dependencies.Keys) {
        if ($visited[$startTaskId]) { continue }

        # Stack entries: @{ TaskId; DepIndex; Path }
        $stack = [System.Collections.ArrayList]@()
        $stack.Add(@{ TaskId = $startTaskId; DepIndex = 0; Path = @($startTaskId) }) | Out-Null
        $recursionStack[$startTaskId] = $true

        while ($stack.Count -gt 0) {
            $current = $stack[$stack.Count - 1]
            $taskId = $current.TaskId
            $depIndex = $current.DepIndex
            $currentPath = $current.Path

            $deps = $dependencies[$taskId]
            if (-not $deps) { $deps = @() }

            if ($depIndex -ge $deps.Count) {
                # Done with this node - backtrack
                $stack.RemoveAt($stack.Count - 1)
                $recursionStack[$taskId] = $false
                $visited[$taskId] = $true
                continue
            }

            # Process next dependency
            $depId = $deps[$depIndex]
            $current.DepIndex = $depIndex + 1

            if ($recursionStack[$depId]) {
                # Found cycle
                $cycleStart = [array]::IndexOf($currentPath, $depId)
                if ($cycleStart -ge 0) {
                    $result.CyclePath = @($currentPath[$cycleStart..($currentPath.Count - 1)]) + @($depId)
                } else {
                    $result.CyclePath = @($currentPath) + @($depId)
                }
                $result.HasCycle = $true
                return $result
            }

            if (-not $visited[$depId] -and $dependencies.ContainsKey($depId)) {
                # Push new node to stack
                $recursionStack[$depId] = $true
                $newPath = @($currentPath) + @($depId)
                $stack.Add(@{ TaskId = $depId; DepIndex = 0; Path = $newPath }) | Out-Null
            }
        }
    }

    return $result
}

function Build-DependencyGraph {
    <#
    .SYNOPSIS
        Builds a dependency graph structure from task dependencies
    .PARAMETER Prd
        The PRD object with tasks
    .OUTPUTS
        Hashtable representing the dependency graph:
        - nodes: array of task IDs
        - edges: array of {from, to} objects
        - adjacencyList: hashtable of taskId -> dependents (tasks that depend on this one)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Prd
    )

    $graph = @{
        nodes = @()
        edges = @()
        adjacencyList = @{}
    }

    if (-not $Prd.tasks) {
        return $graph
    }

    # Collect all task IDs
    foreach ($task in $Prd.tasks) {
        $graph.nodes += $task.id
        $graph.adjacencyList[$task.id] = @()

        if ($task.subtasks) {
            foreach ($subtask in $task.subtasks) {
                $graph.nodes += $subtask.id
                $graph.adjacencyList[$subtask.id] = @()
            }
        }
    }

    # Build edges and adjacency list
    foreach ($task in $Prd.tasks) {
        $tasksToProcess = @($task)
        if ($task.subtasks) {
            $tasksToProcess += $task.subtasks
        }

        foreach ($t in $tasksToProcess) {
            if ($t.dependencies) {
                foreach ($depId in $t.dependencies) {
                    # Edge goes from dependency to dependent
                    $graph.edges += @{ from = $depId; to = $t.id }

                    # Add to adjacency list (what tasks depend on this one)
                    if ($graph.adjacencyList.ContainsKey($depId)) {
                        $graph.adjacencyList[$depId] += $t.id
                    }
                }
            }
        }
    }

    return $graph
}

function Get-NextAvailableTask {
    <#
    .SYNOPSIS
        Returns the next task that has all dependencies satisfied
    .PARAMETER Prd
        The PRD object with tasks
    .OUTPUTS
        The next available task, or $null if none available
    .DESCRIPTION
        A task is available if:
        1. Its status is "pending" or "in_progress"
        2. All tasks in its dependencies array have status "completed"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Prd
    )

    if (-not $Prd.tasks) {
        return $null
    }

    # Build map of task IDs to status
    $taskStatus = @{}
    foreach ($task in $Prd.tasks) {
        $taskStatus[$task.id] = $task.status

        if ($task.subtasks) {
            foreach ($subtask in $task.subtasks) {
                $taskStatus[$subtask.id] = $subtask.status
            }
        }
    }

    # Find first available task (pending/in_progress with all deps completed)
    foreach ($task in $Prd.tasks) {
        # Check top-level task
        if ($task.status -eq "pending" -or $task.status -eq "in_progress") {
            $depsOk = $true
            if ($task.dependencies) {
                foreach ($depId in $task.dependencies) {
                    if ($taskStatus[$depId] -ne "completed") {
                        $depsOk = $false
                        break
                    }
                }
            }
            if ($depsOk) {
                return $task
            }
        }

        # Check subtasks
        if ($task.subtasks) {
            foreach ($subtask in $task.subtasks) {
                if ($subtask.status -eq "pending" -or $subtask.status -eq "in_progress") {
                    $depsOk = $true
                    if ($subtask.dependencies) {
                        foreach ($depId in $subtask.dependencies) {
                            if ($taskStatus[$depId] -ne "completed") {
                                $depsOk = $false
                                break
                            }
                        }
                    }
                    if ($depsOk) {
                        return $subtask
                    }
                }
            }
        }
    }

    return $null
}

function Update-TaskStatus {
    <#
    .SYNOPSIS
        Updates the status of a task in the PRD
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [ValidateSet("pending", "in_progress", "completed", "blocked")]
        [string]$Status,

        [string]$ProjectPath = (Get-Location).Path
    )

    $prd = Get-RalphPrd -ProjectPath $ProjectPath
    if (-not $prd) {
        Write-RalphLog "No PRD found" -Level "ERROR"
        return
    }

    # Search top-level tasks and subtasks
    $task = $prd.tasks | Where-Object { $_.id -eq $TaskId }
    if (-not $task) {
        foreach ($t in $prd.tasks) {
            if ($t.subtasks) {
                $task = $t.subtasks | Where-Object { $_.id -eq $TaskId }
                if ($task) { break }
            }
        }
    }
    if ($task) {
        $task.status = $Status
        Save-RalphPrd -Prd $prd -ProjectPath $ProjectPath
        Write-RalphLog "Task $TaskId status updated to: $Status" -Level "INFO"
    } else {
        Write-RalphLog "Task $TaskId not found" -Level "WARN"
    }
}

# ============================================================================
# SIGNAL PARSING
# ============================================================================

function Find-CompletionSignal {
    <#
    .SYNOPSIS
        Finds PROMISE completion signals in Claude's output
    .PARAMETER Output
        Claude's output text to search
    .DESCRIPTION
        Looks for <PROMISE>COMPLETE</PROMISE> or <PROMISE>BLOCKED</PROMISE>
        Case-insensitive and whitespace-tolerant
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output
    )

    # Flexible regex: case-insensitive, whitespace-tolerant
    $pattern = '<\s*promise\s*>\s*(COMPLETE|BLOCKED)\s*<\s*/\s*promise\s*>'

    if ($Output -match $pattern) {
        return $Matches[1].ToUpper()
    }

    return $null
}

function Find-BlockerReason {
    <#
    .SYNOPSIS
        Extracts blocker reason from Claude's output
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output
    )

    # Look for blocker reason in various formats
    $patterns = @(
        '<\s*blocker\s*>\s*(.+?)\s*<\s*/\s*blocker\s*>',
        'BLOCKED:\s*(.+?)(?:\n|$)',
        'Blocker:\s*(.+?)(?:\n|$)'
    )

    foreach ($pattern in $patterns) {
        if ($Output -match $pattern) {
            return $Matches[1].Trim()
        }
    }

    return $null
}

# ============================================================================
# RATE LIMITING
# ============================================================================

function Get-CallTimestamps {
    <#
    .SYNOPSIS
        Gets call timestamps from file
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $tsPath = Join-Path $ralphPath $script:TimestampsFile

    if (-not (Test-Path $tsPath)) {
        return @()
    }

    try {
        $content = Get-Content -Path $tsPath -Raw
        $data = $content | ConvertFrom-Json
        return @($data)
    } catch {
        return @()
    }
}

function Save-CallTimestamps {
    <#
    .SYNOPSIS
        Saves call timestamps atomically
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [array]$Timestamps = @(),

        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $tsPath = Join-Path $ralphPath $script:TimestampsFile
    $tempPath = "$tsPath.tmp"

    try {
        $json = $Timestamps | ConvertTo-Json -Depth 5
        if (-not $json -or $json -eq "null") {
            $json = "[]"
        }
        Set-Content -Path $tempPath -Value $json -Force
        Move-Item -Path $tempPath -Destination $tsPath -Force
    } catch {
        Write-RalphLog "Failed to save timestamps: $_" -Level "ERROR"
    }
}

function Add-CallTimestamp {
    <#
    .SYNOPSIS
        Records a new API call timestamp
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $timestamps = @(Get-CallTimestamps -ProjectPath $ProjectPath)
    $timestamps += (Get-Date).ToString("o")
    Save-CallTimestamps -Timestamps $timestamps -ProjectPath $ProjectPath
}

function Test-RateLimitOk {
    <#
    .SYNOPSIS
        Checks if we're within rate limits
    .OUTPUTS
        Hashtable with:
        - Ok: boolean
        - WaitSeconds: seconds to wait if not ok
        - CallsInWindow: current call count
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $config = Get-RalphConfig -ProjectPath $ProjectPath
    $maxCalls = $config.rateLimiting.maxCallsPerHour

    $timestamps = @(Get-CallTimestamps -ProjectPath $ProjectPath)
    $oneHourAgo = (Get-Date).AddHours(-1)

    # Filter to calls within the last hour
    $recentCalls = @($timestamps | Where-Object {
        try {
            [datetime]$_ -gt $oneHourAgo
        } catch {
            $false
        }
    })

    # Prune old timestamps
    if ($recentCalls.Count -ne $timestamps.Count) {
        Save-CallTimestamps -Timestamps $recentCalls -ProjectPath $ProjectPath
    }

    $result = @{
        Ok = $true
        WaitSeconds = 0
        CallsInWindow = $recentCalls.Count
    }

    if ($recentCalls.Count -ge $maxCalls) {
        $result.Ok = $false

        # Calculate wait time until oldest call ages out
        $oldestCall = [datetime]($recentCalls | Sort-Object | Select-Object -First 1)
        $waitUntil = $oldestCall.AddHours(1)
        $result.WaitSeconds = [math]::Ceiling(($waitUntil - (Get-Date)).TotalSeconds)

        if ($result.WaitSeconds -lt 0) {
            $result.WaitSeconds = 0
            $result.Ok = $true
        }
    }

    return $result
}

# ============================================================================
# PORT MANAGEMENT
# ============================================================================

function Find-AvailablePort {
    <#
    .SYNOPSIS
        Finds an available port starting from a base port
    .PARAMETER StartPort
        Port to start searching from
    #>
    [CmdletBinding()]
    param(
        [int]$StartPort = 4001
    )

    $port = $StartPort
    $maxPort = $StartPort + 100

    while ($port -lt $maxPort) {
        # Check if port is in use using netstat (works for all interfaces including IPv6)
        $inUse = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if (-not $inUse) {
            # Double-check by trying to bind
            try {
                $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
                $listener.Start()
                $listener.Stop()
                return $port
            } catch {
                # Port became unavailable, try next
            }
        }
        $port++
    }

    Write-RalphLog "No available ports found in range $StartPort-$maxPort" -Level "ERROR"
    return $null
}

function Test-PortInUse {
    <#
    .SYNOPSIS
        Checks if a port is in use (checks both IPv4 and IPv6)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    # Try IPv4 any interface
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
        $listener.Start()
        $listener.Stop()
    } catch {
        return $true
    }

    # Try IPv6 any interface (if supported)
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::IPv6Any, $Port)
        $listener.Start()
        $listener.Stop()
    } catch {
        return $true
    }

    return $false
}

function Test-ApiHealth {
    <#
    .SYNOPSIS
        Checks if an API endpoint is responding
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    try {
        $response = Invoke-RestMethod -Uri "http://localhost:$Port/api/health" -TimeoutSec 2
        return $true
    } catch {
        return $false
    }
}

# ============================================================================
# GIT OPERATIONS
# ============================================================================

function Initialize-GitRepo {
    <#
    .SYNOPSIS
        Initializes a git repository if needed
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    Push-Location $ProjectPath
    try {
        $isGitRepo = git rev-parse --git-dir 2>$null
        if (-not $isGitRepo) {
            git init 2>&1 | Out-Null
            Write-RalphLog "Initialized git repository" -Level "INFO"
        }
    } finally {
        Pop-Location
    }
}

function Get-GitChanges {
    <#
    .SYNOPSIS
        Gets list of changed files since last commit
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    Push-Location $ProjectPath
    try {
        $status = git status --porcelain 2>$null
        if ($status) {
            return @($status | ForEach-Object {
                $parts = $_.Trim() -split '\s+', 2
                @{
                    Status = $parts[0]
                    Path = $parts[1]
                }
            })
        }
        return @()
    } finally {
        Pop-Location
    }
}

function New-GitCommit {
    <#
    .SYNOPSIS
        Creates a git commit with the given message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$ProjectPath = (Get-Location).Path
    )

    Push-Location $ProjectPath
    try {
        $changes = Get-GitChanges -ProjectPath $ProjectPath
        if ($changes.Count -eq 0) {
            Write-RalphLog "No changes to commit" -Level "DEBUG"
            return $false
        }

        git add -A 2>&1 | Out-Null
        git commit -m $Message 2>&1 | Out-Null
        Write-RalphLog "Created commit: $Message" -Level "INFO"
        return $true
    } catch {
        Write-RalphLog "Failed to create commit: $_" -Level "ERROR"
        return $false
    } finally {
        Pop-Location
    }
}

function Get-LastCommitHash {
    <#
    .SYNOPSIS
        Gets the last commit hash
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    Push-Location $ProjectPath
    try {
        $hash = git rev-parse HEAD 2>$null
        return $hash
    } catch {
        return $null
    } finally {
        Pop-Location
    }
}

# ============================================================================
# STOP SIGNAL
# ============================================================================

function Set-StopSignal {
    <#
    .SYNOPSIS
        Creates a stop signal file
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $signalPath = Join-Path $ralphPath $script:StopSignalFile

    "STOP" | Set-Content -Path $signalPath -Force
    Write-RalphLog "Stop signal set" -Level "INFO"
}

function Test-StopSignal {
    <#
    .SYNOPSIS
        Checks if stop signal exists
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $signalPath = Join-Path $ralphPath $script:StopSignalFile

    return Test-Path $signalPath
}

function Clear-StopSignal {
    <#
    .SYNOPSIS
        Removes the stop signal file
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $signalPath = Join-Path $ralphPath $script:StopSignalFile

    if (Test-Path $signalPath) {
        Remove-Item $signalPath -Force
        Write-RalphLog "Stop signal cleared" -Level "DEBUG"
    }
}

# ============================================================================
# CONVERSATION LOGGING
# ============================================================================

function Get-ConversationLog {
    <#
    .SYNOPSIS
        Gets the conversation log (all prompts and responses)
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path,
        [int]$Limit = 10
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $convPath = Join-Path $ralphPath $script:ConversationsFile

    if (-not (Test-Path $convPath)) {
        return @()
    }

    try {
        $content = Get-Content -Path $convPath -Raw
        $conversations = $content | ConvertFrom-Json

        # Return most recent conversations (limited)
        if ($conversations.Count -gt $Limit) {
            return @($conversations | Select-Object -Last $Limit)
        }
        return @($conversations)
    } catch {
        Write-RalphLog "Failed to read conversation log: $_" -Level "WARN"
        return @()
    }
}

function Add-ConversationEntry {
    <#
    .SYNOPSIS
        Adds a conversation entry (prompt/response pair) to the log
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Iteration,

        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [string]$TaskTitle,

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [string]$Response,

        [string]$Status = "pending",

        [double]$ElapsedMinutes = 0,

        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $convPath = Join-Path $ralphPath $script:ConversationsFile
    $tempPath = "$convPath.tmp"

    # Read existing conversations
    $conversations = @()
    if (Test-Path $convPath) {
        try {
            $content = Get-Content -Path $convPath -Raw
            $existing = $content | ConvertFrom-Json
            $conversations = @($existing)
        } catch {
            # Start fresh if corrupted
            $conversations = @()
        }
    }

    # Create new entry
    $entry = @{
        id = [guid]::NewGuid().ToString()
        iteration = $Iteration
        taskId = $TaskId
        taskTitle = $TaskTitle
        timestamp = (Get-Date).ToString("o")
        prompt = $Prompt
        response = $Response
        status = $Status
        elapsedMinutes = $ElapsedMinutes
    }

    $conversations += $entry

    # Keep only last 50 conversations to prevent unbounded growth
    if ($conversations.Count -gt 50) {
        $conversations = @($conversations | Select-Object -Last 50)
    }

    try {
        $json = $conversations | ConvertTo-Json -Depth 10
        Set-Content -Path $tempPath -Value $json -Force
        Move-Item -Path $tempPath -Destination $convPath -Force
        return $entry.id
    } catch {
        Write-RalphLog "Failed to save conversation entry: $_" -Level "ERROR"
        return $null
    }
}

function Update-ConversationEntry {
    <#
    .SYNOPSIS
        Updates an existing conversation entry with response data
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntryId,

        [string]$Response,

        [string]$Status,

        [double]$ElapsedMinutes,

        [string]$Error,

        [string]$ProjectPath = (Get-Location).Path
    )

    $ralphPath = Get-RalphPath -ProjectPath $ProjectPath
    $convPath = Join-Path $ralphPath $script:ConversationsFile
    $tempPath = "$convPath.tmp"

    if (-not (Test-Path $convPath)) {
        return
    }

    try {
        $content = Get-Content -Path $convPath -Raw
        $conversations = @($content | ConvertFrom-Json)

        for ($i = 0; $i -lt $conversations.Count; $i++) {
            if ($conversations[$i].id -eq $EntryId) {
                # Use Add-Member -Force to handle PSCustomObjects from ConvertFrom-Json
                # which may not have all properties if they were null when saved
                if ($Response) {
                    $conversations[$i] | Add-Member -NotePropertyName 'response' -NotePropertyValue $Response -Force
                }
                if ($Status) {
                    $conversations[$i] | Add-Member -NotePropertyName 'status' -NotePropertyValue $Status -Force
                }
                if ($ElapsedMinutes) {
                    $conversations[$i] | Add-Member -NotePropertyName 'elapsedMinutes' -NotePropertyValue $ElapsedMinutes -Force
                }
                if ($Error) {
                    $conversations[$i] | Add-Member -NotePropertyName 'error' -NotePropertyValue $Error -Force
                }
                $conversations[$i] | Add-Member -NotePropertyName 'completedAt' -NotePropertyValue (Get-Date).ToString("o") -Force
                break
            }
        }

        $json = $conversations | ConvertTo-Json -Depth 10
        Set-Content -Path $tempPath -Value $json -Force
        Move-Item -Path $tempPath -Destination $convPath -Force
    } catch {
        Write-RalphLog "Failed to update conversation entry: $_" -Level "ERROR"
    }
}

# ============================================================================
# CIRCUIT BREAKER
# ============================================================================

function Test-CircuitBreaker {
    <#
    .SYNOPSIS
        Checks if circuit breaker conditions are met
    .OUTPUTS
        Hashtable with:
        - Triggered: boolean
        - Reason: string explaining why (if triggered)
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $config = Get-RalphConfig -ProjectPath $ProjectPath
    $state = Get-RalphState -ProjectPath $ProjectPath

    $result = @{
        Triggered = $false
        Reason = $null
    }

    if (-not $state -or -not $config) {
        return $result
    }

    $cb = $config.circuitBreaker

    # Check no-change iterations
    if ($state.noChangeCount -and $state.noChangeCount -ge $cb.maxNoChangeIterations) {
        $result.Triggered = $true
        $result.Reason = "No changes detected for $($state.noChangeCount) consecutive iterations"
        return $result
    }

    # Check same-error iterations
    if ($state.sameErrorCount -and $state.sameErrorCount -ge $cb.maxSameErrorIterations) {
        $result.Triggered = $true
        $result.Reason = "Same error occurred $($state.sameErrorCount) consecutive times"
        return $result
    }

    # Check total runtime (cumulative active time, not wall clock time)
    if ($state.startTime) {
        $startTime = [datetime]$state.startTime
        $currentSessionMinutes = ((Get-Date) - $startTime).TotalMinutes
        $previousMinutes = if ($state.totalActiveMinutes) { $state.totalActiveMinutes } else { 0 }
        $totalRuntime = $previousMinutes + $currentSessionMinutes
        if ($totalRuntime -ge $cb.maxTotalMinutes) {
            $result.Triggered = $true
            $result.Reason = "Maximum runtime of $($cb.maxTotalMinutes) minutes exceeded (total: $([math]::Round($totalRuntime, 1)) min)"
            return $result
        }
    }

    return $result
}

function Get-TaskTimeoutCount {
    <#
    .SYNOPSIS
        Gets the timeout count for a specific task
    .PARAMETER TaskId
        The task ID to check
    .PARAMETER ProjectPath
        Project path for state lookup
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [string]$ProjectPath = (Get-Location).Path
    )

    $state = Get-RalphState -ProjectPath $ProjectPath
    if (-not $state -or -not $state.taskTimeouts) {
        return 0
    }

    # Handle both hashtable and PSCustomObject (from JSON deserialization)
    if ($state.taskTimeouts -is [hashtable]) {
        if ($state.taskTimeouts.ContainsKey($TaskId)) {
            return $state.taskTimeouts[$TaskId]
        } else {
            return 0
        }
    } else {
        # PSCustomObject from JSON
        $value = $state.taskTimeouts.PSObject.Properties[$TaskId]
        if ($value) {
            return $value.Value
        } else {
            return 0
        }
    }
}

function Add-TaskTimeout {
    <#
    .SYNOPSIS
        Increments the timeout count for a specific task
    .PARAMETER TaskId
        The task ID that timed out
    .PARAMETER ProjectPath
        Project path for state lookup
    .OUTPUTS
        The new timeout count for this task
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [string]$ProjectPath = (Get-Location).Path
    )

    $state = Get-RalphState -ProjectPath $ProjectPath
    if (-not $state) {
        return 1
    }

    # Get current taskTimeouts, handling both hashtable and PSCustomObject
    $taskTimeouts = @{}
    if ($state.taskTimeouts) {
        if ($state.taskTimeouts -is [hashtable]) {
            $taskTimeouts = $state.taskTimeouts.Clone()
        } else {
            # Convert PSCustomObject to hashtable
            foreach ($prop in $state.taskTimeouts.PSObject.Properties) {
                $taskTimeouts[$prop.Name] = $prop.Value
            }
        }
    }

    # Increment count
    $currentCount = if ($taskTimeouts.ContainsKey($TaskId)) { $taskTimeouts[$TaskId] } else { 0 }
    $newCount = $currentCount + 1
    $taskTimeouts[$TaskId] = $newCount

    Update-RalphState -Updates @{ taskTimeouts = $taskTimeouts } -ProjectPath $ProjectPath
    return $newCount
}

function Get-EffectiveTimeout {
    <#
    .SYNOPSIS
        Calculates the effective timeout for a task based on previous timeout history
    .DESCRIPTION
        If a task has timed out before, extends the timeout by timeoutExtensionMinutes
        for each previous timeout (up to maxTaskTimeouts - 1 extensions)
    .PARAMETER TaskId
        The task ID to calculate timeout for
    .PARAMETER ProjectPath
        Project path for config/state lookup
    .OUTPUTS
        Hashtable with:
        - TimeoutMinutes: effective timeout in minutes
        - ExtensionCount: number of extensions applied
        - BaseTimeout: the base timeout from config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [string]$ProjectPath = (Get-Location).Path
    )

    $config = Get-RalphConfig -ProjectPath $ProjectPath
    $baseTimeout = if ($config.iterationTimeoutMinutes) { $config.iterationTimeoutMinutes } else { 15 }
    $extensionMinutes = if ($config.circuitBreaker.timeoutExtensionMinutes) { $config.circuitBreaker.timeoutExtensionMinutes } else { 5 }
    $maxTimeouts = if ($config.circuitBreaker.maxTaskTimeouts) { $config.circuitBreaker.maxTaskTimeouts } else { 3 }

    $timeoutCount = Get-TaskTimeoutCount -TaskId $TaskId -ProjectPath $ProjectPath

    # Max extensions is maxTaskTimeouts - 1 (original attempt + extensions)
    $extensionCount = [math]::Min($timeoutCount, $maxTimeouts - 1)
    $effectiveTimeout = $baseTimeout + ($extensionCount * $extensionMinutes)

    return @{
        TimeoutMinutes = $effectiveTimeout
        ExtensionCount = $extensionCount
        BaseTimeout = $baseTimeout
        PreviousTimeouts = $timeoutCount
    }
}

function Test-TaskTimeoutCircuitBreaker {
    <#
    .SYNOPSIS
        Checks if a task has exceeded its maximum timeout retries
    .PARAMETER TaskId
        The task ID to check
    .PARAMETER ProjectPath
        Project path for config/state lookup
    .OUTPUTS
        Hashtable with:
        - Triggered: boolean
        - Reason: string explaining why (if triggered)
        - TimeoutCount: current timeout count
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [string]$ProjectPath = (Get-Location).Path
    )

    $config = Get-RalphConfig -ProjectPath $ProjectPath
    $maxTimeouts = if ($config.circuitBreaker.maxTaskTimeouts) { $config.circuitBreaker.maxTaskTimeouts } else { 3 }
    $timeoutCount = Get-TaskTimeoutCount -TaskId $TaskId -ProjectPath $ProjectPath

    $result = @{
        Triggered = $false
        Reason = $null
        TimeoutCount = $timeoutCount
    }

    if ($timeoutCount -ge $maxTimeouts) {
        $result.Triggered = $true
        $result.Reason = "Task '$TaskId' timed out $timeoutCount times (max: $maxTimeouts)"
    }

    return $result
}

# ============================================================================
# CLAUDE CLI WRAPPER
# ============================================================================

function Invoke-Claude {
    <#
    .SYNOPSIS
        Invokes Claude CLI with rate limiting, retry logic, timeout, and conversation logging
    .PARAMETER Prompt
        The prompt to send to Claude
    .PARAMETER Model
        Model to use (from config if not specified)
    .PARAMETER MaxTurns
        Maximum turns for the conversation
    .PARAMETER TimeoutMinutes
        Timeout in minutes (from config if not specified)
    .PARAMETER Iteration
        Current iteration number (for logging)
    .PARAMETER TaskId
        Current task ID (for logging)
    .PARAMETER TaskTitle
        Current task title (for logging)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [string]$Model,

        [int]$MaxTurns,

        [int]$TimeoutMinutes,

        [int]$Iteration = 0,

        [string]$TaskId = "unknown",

        [string]$TaskTitle = "Unknown Task",

        [string]$ProjectPath = (Get-Location).Path
    )

    $config = Get-RalphConfig -ProjectPath $ProjectPath

    if (-not $Model) {
        $Model = $config.model
    }

    if (-not $MaxTurns) {
        $MaxTurns = $config.maxTurnsPerIteration
    }

    if (-not $TimeoutMinutes -or $TimeoutMinutes -le 0) {
        $TimeoutMinutes = if ($config.iterationTimeoutMinutes) { $config.iterationTimeoutMinutes } else { 15 }
    }

    $retryCount = $config.rateLimiting.retryCount
    $cooldown = $config.rateLimiting.cooldownSeconds
    $timeoutSeconds = $TimeoutMinutes * 60

    for ($attempt = 0; $attempt -le $retryCount; $attempt++) {
        # Check rate limit
        $rateCheck = Test-RateLimitOk -ProjectPath $ProjectPath
        if (-not $rateCheck.Ok) {
            Write-RalphLog "Rate limit reached. Waiting $($rateCheck.WaitSeconds) seconds..." -Level "WARN"
            Start-Sleep -Seconds $rateCheck.WaitSeconds
        }

        # Record call timestamp
        Add-CallTimestamp -ProjectPath $ProjectPath

        try {
            Write-RalphLog "Invoking Claude (attempt $($attempt + 1), timeout: ${TimeoutMinutes}m)..." -Level "DEBUG"

            # Update state with iteration start time
            Update-RalphState -Updates @{
                iterationStartTime = (Get-Date).ToString("o")
                iterationStatus = "running"
            } -ProjectPath $ProjectPath

            # Create conversation log entry
            $convEntryId = Add-ConversationEntry `
                -Iteration $Iteration `
                -TaskId $TaskId `
                -TaskTitle $TaskTitle `
                -Prompt $Prompt `
                -Status "running" `
                -ProjectPath $ProjectPath

            # Write prompt to temp file to avoid command line length limits
            $tempPromptFile = [System.IO.Path]::GetTempFileName()
            Set-Content -Path $tempPromptFile -Value $Prompt -Encoding UTF8

            # Use Start-Process with timeout for better control
            $outputFile = [System.IO.Path]::GetTempFileName()
            $errorFile = [System.IO.Path]::GetTempFileName()

            $processArgs = "-p `"$tempPromptFile`" --model $Model --max-turns $MaxTurns --dangerously-skip-permissions --output-format json"

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "claude"
            $psi.Arguments = "-p `"$(Get-Content $tempPromptFile -Raw)`" --model $Model --max-turns $MaxTurns --dangerously-skip-permissions --output-format json"
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            $psi.WorkingDirectory = $ProjectPath

            $process = [System.Diagnostics.Process]::Start($psi)

            # Poll for completion with timeout, updating state periodically
            $startTime = Get-Date
            $lastStatusUpdate = $startTime
            $statusUpdateInterval = 30  # Update state every 30 seconds

            while (-not $process.HasExited) {
                $elapsed = (Get-Date) - $startTime
                $elapsedMinutes = [math]::Round($elapsed.TotalMinutes, 1)

                # Check timeout
                if ($elapsed.TotalSeconds -ge $timeoutSeconds) {
                    Write-RalphLog "Iteration timeout (${TimeoutMinutes}m) exceeded. Killing Claude process..." -Level "WARN"

                    try {
                        $process.Kill()
                        $process.WaitForExit(5000)
                    } catch {
                        Write-RalphLog "Failed to kill process: $_" -Level "ERROR"
                    }

                    # Cleanup temp files
                    Remove-Item $tempPromptFile -Force -ErrorAction SilentlyContinue

                    Update-RalphState -Updates @{
                        iterationStatus = "timeout"
                        iterationElapsedMinutes = $elapsedMinutes
                    } -ProjectPath $ProjectPath

                    # Update conversation log with timeout
                    if ($convEntryId) {
                        Update-ConversationEntry `
                            -EntryId $convEntryId `
                            -Status "timeout" `
                            -ElapsedMinutes $elapsedMinutes `
                            -Error "Iteration timed out after $TimeoutMinutes minutes" `
                            -ProjectPath $ProjectPath
                    }

                    return @{
                        Success = $false
                        Output = $null
                        Error = "Iteration timed out after $TimeoutMinutes minutes"
                        TimedOut = $true
                    }
                }

                # Periodic status update
                if (((Get-Date) - $lastStatusUpdate).TotalSeconds -ge $statusUpdateInterval) {
                    Update-RalphState -Updates @{
                        iterationElapsedMinutes = $elapsedMinutes
                    } -ProjectPath $ProjectPath
                    Write-RalphLog "Iteration in progress: ${elapsedMinutes}m elapsed (timeout: ${TimeoutMinutes}m)" -Level "INFO"
                    $lastStatusUpdate = Get-Date
                }

                Start-Sleep -Milliseconds 500
            }

            # Process completed - read output
            $output = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()

            # Cleanup temp file
            Remove-Item $tempPromptFile -Force -ErrorAction SilentlyContinue

            $elapsedMinutes = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

            Update-RalphState -Updates @{
                iterationStatus = "completed"
                iterationElapsedMinutes = $elapsedMinutes
            } -ProjectPath $ProjectPath

            if ($process.ExitCode -ne 0) {
                Write-RalphLog "Claude process exited with code $($process.ExitCode): $stderr" -Level "ERROR"

                # Update conversation log with error
                if ($convEntryId) {
                    Update-ConversationEntry `
                        -EntryId $convEntryId `
                        -Response $output `
                        -Status "error" `
                        -ElapsedMinutes $elapsedMinutes `
                        -Error "Claude exited with code $($process.ExitCode): $stderr" `
                        -ProjectPath $ProjectPath
                }

                return @{
                    Success = $false
                    Output = $output
                    Error = "Claude exited with code $($process.ExitCode): $stderr"
                }
            }

            Write-RalphLog "Claude completed in ${elapsedMinutes}m, response length: $($output.Length) chars" -Level "DEBUG"

            # Log first part of response for debugging
            $preview = if ($output.Length -gt 200) { $output.Substring(0, 200) + "..." } else { $output }
            Write-RalphLog "Claude response preview: $preview" -Level "DEBUG"

            # Update conversation log with successful response
            if ($convEntryId) {
                Update-ConversationEntry `
                    -EntryId $convEntryId `
                    -Response $output `
                    -Status "completed" `
                    -ElapsedMinutes $elapsedMinutes `
                    -ProjectPath $ProjectPath
            }

            return @{
                Success = $true
                Output = $output
                Error = $null
                ElapsedMinutes = $elapsedMinutes
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Write-RalphLog "Claude invocation failed: $errorMsg" -Level "ERROR"

            Update-RalphState -Updates @{
                iterationStatus = "error"
            } -ProjectPath $ProjectPath

            # Update conversation log with error (if entry was created)
            if ($convEntryId) {
                Update-ConversationEntry `
                    -EntryId $convEntryId `
                    -Status "error" `
                    -Error $errorMsg `
                    -ProjectPath $ProjectPath
            }

            if ($attempt -lt $retryCount) {
                Write-RalphLog "Retrying in $cooldown seconds..." -Level "WARN"
                Start-Sleep -Seconds $cooldown
            } else {
                return @{
                    Success = $false
                    Output = $null
                    Error = $errorMsg
                }
            }
        }
    }
}

# ============================================================================
# CODEX CLI WRAPPER
# ============================================================================

function Invoke-Codex {
    <#
    .SYNOPSIS
        Invokes Codex CLI with rate limiting, retry logic, timeout, and conversation logging
    .PARAMETER Prompt
        The prompt to send to Codex
    .PARAMETER TimeoutMinutes
        Timeout in minutes (from config if not specified)
    .PARAMETER Iteration
        Current iteration number (for logging)
    .PARAMETER TaskId
        Current task ID (for logging)
    .PARAMETER TaskTitle
        Current task title (for logging)
    .DESCRIPTION
        Codex CLI differences from Claude CLI:
        - Command: codex exec "prompt" (not claude -p)
        - Permissions bypass: --dangerously-bypass-approvals-and-sandbox
        - JSON output: --json (returns JSONL format)
        - No --model flag (handled by global config)
        - No --max-turns flag
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [int]$TimeoutMinutes,

        [int]$Iteration = 0,

        [string]$TaskId = "unknown",

        [string]$TaskTitle = "Unknown Task",

        [string]$ProjectPath = (Get-Location).Path
    )

    $config = Get-RalphConfig -ProjectPath $ProjectPath

    if (-not $TimeoutMinutes -or $TimeoutMinutes -le 0) {
        $TimeoutMinutes = if ($config.iterationTimeoutMinutes) { $config.iterationTimeoutMinutes } else { 15 }
    }

    $retryCount = $config.rateLimiting.retryCount
    $cooldown = $config.rateLimiting.cooldownSeconds
    $timeoutSeconds = $TimeoutMinutes * 60

    for ($attempt = 0; $attempt -le $retryCount; $attempt++) {
        # Check rate limit
        $rateCheck = Test-RateLimitOk -ProjectPath $ProjectPath
        if (-not $rateCheck.Ok) {
            Write-RalphLog "Rate limit reached. Waiting $($rateCheck.WaitSeconds) seconds..." -Level "WARN"
            Start-Sleep -Seconds $rateCheck.WaitSeconds
        }

        # Record call timestamp
        Add-CallTimestamp -ProjectPath $ProjectPath

        try {
            Write-RalphLog "Invoking Codex (attempt $($attempt + 1), timeout: ${TimeoutMinutes}m)..." -Level "DEBUG"

            # Update state with iteration start time
            Update-RalphState -Updates @{
                iterationStartTime = (Get-Date).ToString("o")
                iterationStatus = "running"
            } -ProjectPath $ProjectPath

            # Create conversation log entry
            $convEntryId = Add-ConversationEntry `
                -Iteration $Iteration `
                -TaskId $TaskId `
                -TaskTitle $TaskTitle `
                -Prompt $Prompt `
                -Status "running" `
                -ProjectPath $ProjectPath

            # Get model from config if available
            $codexModel = $config.codexModel

            # Build codex args - use stdin via "-" argument
            $codexArgs = "exec - --dangerously-bypass-approvals-and-sandbox --json"
            if ($codexModel) {
                $codexArgs = "exec - -m $codexModel --dangerously-bypass-approvals-and-sandbox --json"
            }

            # Launch codex via cmd.exe to handle .cmd/.ps1 wrappers on Windows.
            # Using cmd /c avoids the powershell.exe wrapper that caused
            # encoding issues and stream disconnects.
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "cmd.exe"
            $psi.Arguments = "/c codex $codexArgs"
            $psi.UseShellExecute = $false
            $psi.RedirectStandardInput = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            $psi.WorkingDirectory = $ProjectPath

            $process = [System.Diagnostics.Process]::Start($psi)

            # Write prompt to stdin and close it so codex knows input is complete
            $process.StandardInput.Write($Prompt)
            $process.StandardInput.Close()

            # Use async reads to prevent deadlock when stdout/stderr buffers fill up.
            # Without this, the child process blocks writing to a full pipe buffer
            # and never exits, causing Ralph to hit the timeout every time.
            $stdoutBuilder = New-Object System.Text.StringBuilder
            $stderrBuilder = New-Object System.Text.StringBuilder

            $stdoutEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action {
                if ($null -ne $EventArgs.Data) {
                    $Event.MessageData.AppendLine($EventArgs.Data)
                }
            } -MessageData $stdoutBuilder

            $stderrEvent = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action {
                if ($null -ne $EventArgs.Data) {
                    $Event.MessageData.AppendLine($EventArgs.Data)
                }
            } -MessageData $stderrBuilder

            $process.BeginOutputReadLine()
            $process.BeginErrorReadLine()

            # Poll for completion with timeout, updating state periodically
            $startTime = Get-Date
            $lastStatusUpdate = $startTime
            $statusUpdateInterval = 30  # Update state every 30 seconds

            while (-not $process.HasExited) {
                $elapsed = (Get-Date) - $startTime
                $elapsedMinutes = [math]::Round($elapsed.TotalMinutes, 1)

                # Check timeout
                if ($elapsed.TotalSeconds -ge $timeoutSeconds) {
                    Write-RalphLog "Iteration timeout (${TimeoutMinutes}m) exceeded. Killing Codex process..." -Level "WARN"

                    try {
                        $process.Kill()
                        $process.WaitForExit(5000)
                    } catch {
                        Write-RalphLog "Failed to kill process: $_" -Level "ERROR"
                    }

                    # Cleanup async event handlers
                    Unregister-Event -SourceIdentifier $stdoutEvent.Name -ErrorAction SilentlyContinue
                    Unregister-Event -SourceIdentifier $stderrEvent.Name -ErrorAction SilentlyContinue

                    Update-RalphState -Updates @{
                        iterationStatus = "timeout"
                        iterationElapsedMinutes = $elapsedMinutes
                    } -ProjectPath $ProjectPath

                    # Update conversation log with timeout
                    if ($convEntryId) {
                        Update-ConversationEntry `
                            -EntryId $convEntryId `
                            -Status "timeout" `
                            -ElapsedMinutes $elapsedMinutes `
                            -Error "Iteration timed out after $TimeoutMinutes minutes" `
                            -ProjectPath $ProjectPath
                    }

                    return @{
                        Success = $false
                        Output = $null
                        Error = "Iteration timed out after $TimeoutMinutes minutes"
                        TimedOut = $true
                    }
                }

                # Periodic status update
                if (((Get-Date) - $lastStatusUpdate).TotalSeconds -ge $statusUpdateInterval) {
                    Update-RalphState -Updates @{
                        iterationElapsedMinutes = $elapsedMinutes
                    } -ProjectPath $ProjectPath
                    Write-RalphLog "Iteration in progress: ${elapsedMinutes}m elapsed (timeout: ${TimeoutMinutes}m)" -Level "INFO"
                    $lastStatusUpdate = Get-Date
                }

                Start-Sleep -Milliseconds 500
            }

            # Wait briefly for async reads to flush remaining data
            $process.WaitForExit()

            # Cleanup async event handlers
            Unregister-Event -SourceIdentifier $stdoutEvent.Name -ErrorAction SilentlyContinue
            Unregister-Event -SourceIdentifier $stderrEvent.Name -ErrorAction SilentlyContinue

            # Collect output from async builders
            $output = $stdoutBuilder.ToString()
            $stderr = $stderrBuilder.ToString()

            $elapsedMinutes = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

            Update-RalphState -Updates @{
                iterationStatus = "completed"
                iterationElapsedMinutes = $elapsedMinutes
            } -ProjectPath $ProjectPath

            if ($process.ExitCode -ne 0) {
                # Codex may exit non-zero but still produce valid output (e.g. stream reconnect errors).
                # Check if we got an agent_message before treating as hard failure.
                $hasAgentMessage = $output -match '"type":"agent_message"'
                if ($hasAgentMessage) {
                    Write-RalphLog "Codex exited with code $($process.ExitCode) but produced output. Treating as success. stderr: $($stderr.Substring(0, [Math]::Min(200, $stderr.Length)))" -Level "WARN"
                } else {
                    Write-RalphLog "Codex process exited with code $($process.ExitCode): $stderr" -Level "ERROR"

                    # Update conversation log with error
                    if ($convEntryId) {
                        Update-ConversationEntry `
                            -EntryId $convEntryId `
                            -Response $output `
                            -Status "error" `
                            -ElapsedMinutes $elapsedMinutes `
                            -Error "Codex exited with code $($process.ExitCode): $stderr" `
                            -ProjectPath $ProjectPath
                    }

                    return @{
                        Success = $false
                        Output = $output
                        Error = "Codex exited with code $($process.ExitCode): $stderr"
                    }
                }
            }

            # Parse Codex JSONL output - extract the response content
            # Codex returns JSONL (one JSON object per line)
            # Example output:
            #   {"type":"thread.started","thread_id":"..."}
            #   {"type":"item.completed","item":{"type":"error","message":"Under-development features..."}}
            #   {"type":"turn.started"}
            #   {"type":"item.completed","item":{"type":"agent_message","text":"actual response"}}
            #   {"type":"turn.completed","usage":{...}}
            $parsedOutput = $null
            $outputLines = $output -split "`n" | Where-Object { $_.Trim() }
            foreach ($line in $outputLines) {
                try {
                    $jsonObj = $line | ConvertFrom-Json
                    # Primary Codex format: agent_message contains the actual response
                    if ($jsonObj.type -eq "item.completed" -and $jsonObj.item.type -eq "agent_message" -and $jsonObj.item.text) {
                        $parsedOutput = $jsonObj.item.text
                    }
                    # Skip error/warning items (e.g. "Under-development features" warnings)
                    elseif ($jsonObj.type -eq "item.completed" -and $jsonObj.item.type -eq "error") {
                        Write-RalphLog "Codex warning/error item: $($jsonObj.item.message)" -Level "DEBUG"
                    }
                } catch {
                    # Not valid JSON, skip
                }
            }

            # If we couldn't parse structured output, use raw output
            if (-not $parsedOutput) {
                $parsedOutput = $output
            }

            Write-RalphLog "Codex completed in ${elapsedMinutes}m, response length: $($parsedOutput.Length) chars" -Level "DEBUG"

            # Log first part of response for debugging
            $preview = if ($parsedOutput.Length -gt 200) { $parsedOutput.Substring(0, 200) + "..." } else { $parsedOutput }
            Write-RalphLog "Codex response preview: $preview" -Level "DEBUG"

            # Update conversation log with successful response
            if ($convEntryId) {
                Update-ConversationEntry `
                    -EntryId $convEntryId `
                    -Response $parsedOutput `
                    -Status "completed" `
                    -ElapsedMinutes $elapsedMinutes `
                    -ProjectPath $ProjectPath
            }

            return @{
                Success = $true
                Output = $parsedOutput
                Error = $null
                ElapsedMinutes = $elapsedMinutes
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Write-RalphLog "Codex invocation failed: $errorMsg" -Level "ERROR"

            Update-RalphState -Updates @{
                iterationStatus = "error"
            } -ProjectPath $ProjectPath

            # Update conversation log with error (if entry was created)
            if ($convEntryId) {
                Update-ConversationEntry `
                    -EntryId $convEntryId `
                    -Status "error" `
                    -Error $errorMsg `
                    -ProjectPath $ProjectPath
            }

            if ($attempt -lt $retryCount) {
                Write-RalphLog "Retrying in $cooldown seconds..." -Level "WARN"
                Start-Sleep -Seconds $cooldown
            } else {
                return @{
                    Success = $false
                    Output = $null
                    Error = $errorMsg
                }
            }
        }
    }
}

# ============================================================================
# OPENCODE CLI WRAPPER
# ============================================================================

function Invoke-OpenCode {
    <#
    .SYNOPSIS
        Invokes OpenCode CLI with rate limiting, retry logic, timeout, and conversation logging
    .PARAMETER Prompt
        The prompt to send to OpenCode
    .PARAMETER TimeoutMinutes
        Timeout in minutes (from config if not specified)
    .PARAMETER Iteration
        Current iteration number (for logging)
    .PARAMETER TaskId
        Current task ID (for logging)
    .PARAMETER TaskTitle
        Current task title (for logging)
    .DESCRIPTION
        OpenCode CLI:
        - Command: opencode run "prompt"
        - Model: -m provider/model (optional, uses default if not set)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [int]$TimeoutMinutes,

        [int]$Iteration = 0,

        [string]$TaskId = "unknown",

        [string]$TaskTitle = "Unknown Task",

        [string]$ProjectPath = (Get-Location).Path
    )

    $config = Get-RalphConfig -ProjectPath $ProjectPath

    if (-not $TimeoutMinutes -or $TimeoutMinutes -le 0) {
        $TimeoutMinutes = if ($config.iterationTimeoutMinutes) { $config.iterationTimeoutMinutes } else { 15 }
    }

    $retryCount = $config.rateLimiting.retryCount
    $cooldown = $config.rateLimiting.cooldownSeconds
    $timeoutSeconds = $TimeoutMinutes * 60

    for ($attempt = 0; $attempt -le $retryCount; $attempt++) {
        # Check rate limit
        $rateCheck = Test-RateLimitOk -ProjectPath $ProjectPath
        if (-not $rateCheck.Ok) {
            Write-RalphLog "Rate limit reached. Waiting $($rateCheck.WaitSeconds) seconds..." -Level "WARN"
            Start-Sleep -Seconds $rateCheck.WaitSeconds
        }

        # Record call timestamp
        Add-CallTimestamp -ProjectPath $ProjectPath

        try {
            Write-RalphLog "Invoking OpenCode (attempt $($attempt + 1), timeout: ${TimeoutMinutes}m)..." -Level "DEBUG"

            # Update state with iteration start time
            Update-RalphState -Updates @{
                iterationStartTime = (Get-Date).ToString("o")
                iterationStatus = "running"
            } -ProjectPath $ProjectPath

            # Create conversation log entry
            $convEntryId = Add-ConversationEntry `
                -Iteration $Iteration `
                -TaskId $TaskId `
                -TaskTitle $TaskTitle `
                -Prompt $Prompt `
                -Status "running" `
                -ProjectPath $ProjectPath

            # Write prompt to temp file to avoid command line length limits
            $tempPromptFile = [System.IO.Path]::GetTempFileName()
            Set-Content -Path $tempPromptFile -Value $Prompt -Encoding UTF8

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "opencode"
            # OpenCode uses: opencode run "prompt"
            $psi.Arguments = "run `"$(Get-Content $tempPromptFile -Raw)`""
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            $psi.WorkingDirectory = $ProjectPath

            $process = [System.Diagnostics.Process]::Start($psi)

            # Poll for completion with timeout, updating state periodically
            $startTime = Get-Date
            $lastStatusUpdate = $startTime
            $statusUpdateInterval = 30  # Update state every 30 seconds

            while (-not $process.HasExited) {
                $elapsed = (Get-Date) - $startTime
                $elapsedMinutes = [math]::Round($elapsed.TotalMinutes, 1)

                # Check timeout
                if ($elapsed.TotalSeconds -ge $timeoutSeconds) {
                    Write-RalphLog "Iteration timeout (${TimeoutMinutes}m) exceeded. Killing OpenCode process..." -Level "WARN"

                    try {
                        $process.Kill()
                        $process.WaitForExit(5000)
                    } catch {
                        Write-RalphLog "Failed to kill process: $_" -Level "ERROR"
                    }

                    # Cleanup temp files
                    Remove-Item $tempPromptFile -Force -ErrorAction SilentlyContinue

                    Update-RalphState -Updates @{
                        iterationStatus = "timeout"
                        iterationElapsedMinutes = $elapsedMinutes
                    } -ProjectPath $ProjectPath

                    # Update conversation log with timeout
                    if ($convEntryId) {
                        Update-ConversationEntry `
                            -EntryId $convEntryId `
                            -Status "timeout" `
                            -ElapsedMinutes $elapsedMinutes `
                            -Error "Iteration timed out after $TimeoutMinutes minutes" `
                            -ProjectPath $ProjectPath
                    }

                    return @{
                        Success = $false
                        Output = $null
                        Error = "Iteration timed out after $TimeoutMinutes minutes"
                        TimedOut = $true
                    }
                }

                # Periodic status update
                if (((Get-Date) - $lastStatusUpdate).TotalSeconds -ge $statusUpdateInterval) {
                    Update-RalphState -Updates @{
                        iterationElapsedMinutes = $elapsedMinutes
                    } -ProjectPath $ProjectPath
                    Write-RalphLog "Iteration in progress: ${elapsedMinutes}m elapsed (timeout: ${TimeoutMinutes}m)" -Level "INFO"
                    $lastStatusUpdate = Get-Date
                }

                Start-Sleep -Milliseconds 500
            }

            # Process completed - read output
            $output = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()

            # Cleanup temp file
            Remove-Item $tempPromptFile -Force -ErrorAction SilentlyContinue

            $elapsedMinutes = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

            Update-RalphState -Updates @{
                iterationStatus = "completed"
                iterationElapsedMinutes = $elapsedMinutes
            } -ProjectPath $ProjectPath

            if ($process.ExitCode -ne 0) {
                Write-RalphLog "OpenCode process exited with code $($process.ExitCode): $stderr" -Level "ERROR"

                # Update conversation log with error
                if ($convEntryId) {
                    Update-ConversationEntry `
                        -EntryId $convEntryId `
                        -Response $output `
                        -Status "error" `
                        -ElapsedMinutes $elapsedMinutes `
                        -Error "OpenCode exited with code $($process.ExitCode): $stderr" `
                        -ProjectPath $ProjectPath
                }

                return @{
                    Success = $false
                    Output = $output
                    Error = "OpenCode exited with code $($process.ExitCode): $stderr"
                }
            }

            Write-RalphLog "OpenCode completed in ${elapsedMinutes}m, response length: $($output.Length) chars" -Level "DEBUG"

            # Log first part of response for debugging
            $preview = if ($output.Length -gt 200) { $output.Substring(0, 200) + "..." } else { $output }
            Write-RalphLog "OpenCode response preview: $preview" -Level "DEBUG"

            # Update conversation log with successful response
            if ($convEntryId) {
                Update-ConversationEntry `
                    -EntryId $convEntryId `
                    -Response $output `
                    -Status "completed" `
                    -ElapsedMinutes $elapsedMinutes `
                    -ProjectPath $ProjectPath
            }

            return @{
                Success = $true
                Output = $output
                Error = $null
                ElapsedMinutes = $elapsedMinutes
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Write-RalphLog "OpenCode invocation failed: $errorMsg" -Level "ERROR"

            Update-RalphState -Updates @{
                iterationStatus = "error"
            } -ProjectPath $ProjectPath

            # Update conversation log with error (if entry was created)
            if ($convEntryId) {
                Update-ConversationEntry `
                    -EntryId $convEntryId `
                    -Status "error" `
                    -Error $errorMsg `
                    -ProjectPath $ProjectPath
            }

            if ($attempt -lt $retryCount) {
                Write-RalphLog "Retrying in $cooldown seconds..." -Level "WARN"
                Start-Sleep -Seconds $cooldown
            } else {
                return @{
                    Success = $false
                    Output = $null
                    Error = $errorMsg
                }
            }
        }
    }
}

# ============================================================================
# ENGINE WRAPPER (dispatches to Claude, Codex, or OpenCode)
# ============================================================================

function Invoke-Engine {
    <#
    .SYNOPSIS
        Invokes the configured engine (Claude, Codex, or OpenCode)
    .DESCRIPTION
        Wrapper function that dispatches to Invoke-Claude, Invoke-Codex, or Invoke-OpenCode
        based on the engine setting in config or the override parameter
    .PARAMETER Prompt
        The prompt to send
    .PARAMETER Engine
        Override engine selection ("claude", "codex", or "opencode")
    .PARAMETER Model
        Model to use (Claude only)
    .PARAMETER MaxTurns
        Maximum turns (Claude only)
    .PARAMETER TimeoutMinutes
        Timeout in minutes
    .PARAMETER Iteration
        Current iteration number (for logging)
    .PARAMETER TaskId
        Current task ID (for logging)
    .PARAMETER TaskTitle
        Current task title (for logging)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [ValidateSet("claude", "codex", "opencode")]
        [string]$Engine,

        [string]$Model,

        [int]$MaxTurns,

        [int]$TimeoutMinutes,

        [int]$Iteration = 0,

        [string]$TaskId = "unknown",

        [string]$TaskTitle = "Unknown Task",

        [string]$ProjectPath = (Get-Location).Path
    )

    $config = Get-RalphConfig -ProjectPath $ProjectPath

    # Determine which engine to use
    $selectedEngine = if ($Engine) { $Engine } else { $config.engine }
    if (-not $selectedEngine) {
        $selectedEngine = "claude"  # Default to Claude
    }

    Write-RalphLog "Using engine: $selectedEngine" -Level "DEBUG"

    if ($selectedEngine -eq "codex") {
        return Invoke-Codex `
            -Prompt $Prompt `
            -TimeoutMinutes $TimeoutMinutes `
            -Iteration $Iteration `
            -TaskId $TaskId `
            -TaskTitle $TaskTitle `
            -ProjectPath $ProjectPath
    } elseif ($selectedEngine -eq "opencode") {
        return Invoke-OpenCode `
            -Prompt $Prompt `
            -TimeoutMinutes $TimeoutMinutes `
            -Iteration $Iteration `
            -TaskId $TaskId `
            -TaskTitle $TaskTitle `
            -ProjectPath $ProjectPath
    } else {
        return Invoke-Claude `
            -Prompt $Prompt `
            -Model $Model `
            -MaxTurns $MaxTurns `
            -TimeoutMinutes $TimeoutMinutes `
            -Iteration $Iteration `
            -TaskId $TaskId `
            -TaskTitle $TaskTitle `
            -ProjectPath $ProjectPath
    }
}

function Invoke-EngineSimple {
    <#
    .SYNOPSIS
        Simple one-shot engine invocation for PRD transformation
    .DESCRIPTION
        Simpler wrapper for non-iteration uses like PRD transformation.
        Does not track conversation logs or iteration state.
    .PARAMETER Prompt
        The prompt to send
    .PARAMETER Engine
        Override engine selection ("claude", "codex", or "opencode")
    .PARAMETER ProjectPath
        Project path for config lookup
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [ValidateSet("claude", "codex", "opencode")]
        [string]$Engine,

        [string]$ProjectPath = (Get-Location).Path
    )

    $config = Get-RalphConfig -ProjectPath $ProjectPath

    # Determine which engine to use
    $selectedEngine = if ($Engine) { $Engine } else { $config.engine }
    if (-not $selectedEngine) {
        $selectedEngine = "claude"  # Default to Claude
    }

    Write-RalphLog "Using engine for simple invocation: $selectedEngine" -Level "DEBUG"

    if ($selectedEngine -eq "codex") {
        # Codex: Pass prompt via stdin to avoid all escaping issues
        # codex exec - --dangerously-bypass-approvals-and-sandbox --json
        $currentLocation = Get-Location
        $tempStderrFile = [System.IO.Path]::GetTempFileName()
        try {
            Set-Location $ProjectPath
            # Get model from config if available
            $codexModel = $config.codexModel

            # Use & operator with stdin piping, redirect stderr to file to avoid log pollution
            if ($codexModel) {
                $jsonContent = $Prompt | & codex exec - -m $codexModel --dangerously-bypass-approvals-and-sandbox --json 2>$tempStderrFile
            } else {
                $jsonContent = $Prompt | & codex exec - --dangerously-bypass-approvals-and-sandbox --json 2>$tempStderrFile
            }
            $jsonContent = $jsonContent | Out-String

            # If stdout is empty, check stderr for debugging
            if (-not $jsonContent) {
                $stderrContent = Get-Content $tempStderrFile -Raw -ErrorAction SilentlyContinue
                if ($stderrContent) {
                    Write-RalphLog "Codex stderr: $($stderrContent.Substring(0, [Math]::Min(500, $stderrContent.Length)))" -Level "DEBUG"
                }
            }
        } finally {
            Set-Location $currentLocation
            Remove-Item $tempStderrFile -Force -ErrorAction SilentlyContinue
        }

        # Parse JSONL output - codex outputs multiple JSON lines
        # Skip error/warning items, only extract agent_message text
        $outputLines = $jsonContent -split "`n" | Where-Object { $_.Trim() }
        foreach ($line in $outputLines) {
            try {
                $jsonObj = $line | ConvertFrom-Json
                # Primary Codex format: agent_message contains the actual response
                if ($jsonObj.type -eq "item.completed" -and $jsonObj.item.type -eq "agent_message" -and $jsonObj.item.text) {
                    return $jsonObj.item.text
                }
                # Skip error/warning items (e.g. "Under-development features" warnings)
                elseif ($jsonObj.type -eq "item.completed" -and $jsonObj.item.type -eq "error") {
                    Write-RalphLog "Codex warning/error item: $($jsonObj.item.message)" -Level "DEBUG"
                }
            } catch {
                # Not valid JSON, skip
            }
        }
        # Fallback to raw output
        return $jsonContent
    } elseif ($selectedEngine -eq "opencode") {
        # OpenCode: opencode run "prompt" - use temp file approach
        $tempPromptFile = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -Path $tempPromptFile -Value $Prompt -Encoding UTF8
            $promptContent = Get-Content $tempPromptFile -Raw
            $result = & opencode run $promptContent 2>&1
        } finally {
            Remove-Item $tempPromptFile -Force -ErrorAction SilentlyContinue
        }
        return $result | Out-String
    } else {
        # Claude: claude -p "prompt" --output-format json - use temp file approach
        $tempPromptFile = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -Path $tempPromptFile -Value $Prompt -Encoding UTF8
            $promptContent = Get-Content $tempPromptFile -Raw
            $result = & claude -p $promptContent --output-format json 2>&1
        } finally {
            Remove-Item $tempPromptFile -Force -ErrorAction SilentlyContinue
        }
        return $result | Out-String
    }
}

# ============================================================================
# EXPORTS (only when loaded as module)
# ============================================================================

if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        # Logging
        'Write-RalphLog',
        'Get-RalphLogTail',

        # Path utilities
        'Get-RalphPath',
        'Test-RalphExists',
        'Initialize-RalphDirectory',

        # State management
        'Get-RalphState',
        'Save-RalphState',
        'Update-RalphState',

        # Config management
        'Get-RalphConfig',
        'Save-RalphConfig',

        # PRD management
        'Get-RalphPrd',
        'Save-RalphPrd',
        'ConvertFrom-MarkdownPrd',
        'Update-TaskStatus',

        # Dependency management
        'Test-DependencyValidation',
        'Test-CircularDependencies',
        'Build-DependencyGraph',
        'Get-NextAvailableTask',

        # Signal parsing
        'Find-CompletionSignal',
        'Find-BlockerReason',

        # Rate limiting
        'Get-CallTimestamps',
        'Save-CallTimestamps',
        'Add-CallTimestamp',
        'Test-RateLimitOk',

        # Port management
        'Find-AvailablePort',
        'Test-PortInUse',
        'Test-ApiHealth',

        # Git operations
        'Initialize-GitRepo',
        'Get-GitChanges',
        'New-GitCommit',
        'Get-LastCommitHash',

        # Stop signal
        'Set-StopSignal',
        'Test-StopSignal',
        'Clear-StopSignal',

        # Circuit breaker
        'Test-CircuitBreaker',

        # Conversation logging
        'Get-ConversationLog',
        'Add-ConversationEntry',
        'Update-ConversationEntry',

        # Claude CLI
        'Invoke-Claude',

        # Codex CLI
        'Invoke-Codex',

        # OpenCode CLI
        'Invoke-OpenCode',

        # Engine wrapper
        'Invoke-Engine',
        'Invoke-EngineSimple'
    )
}
