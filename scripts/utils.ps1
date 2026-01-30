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
            apiPort = $null
            errors = @()
            noChangeCount = 0
            sameErrorCount = 0
            lastError = $null
            filesChanged = @()
            testResults = $null
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
    .DESCRIPTION
        Uses Claude to transform a markdown PRD into the structured JSON format
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MarkdownPath
    )

    if (-not (Test-Path $MarkdownPath)) {
        Write-RalphLog "Markdown file not found: $MarkdownPath" -Level "ERROR"
        return $null
    }

    $mdContent = Get-Content -Path $MarkdownPath -Raw

    $transformPrompt = @"
You are a JSON generator. Your ONLY output must be valid JSON - no explanations, no markdown, no text before or after.

Convert this PRD to JSON with this structure:
{"projectName":"string","description":"string","tasks":[{"id":1,"title":"string","description":"string","status":"pending","acceptanceCriteria":["string"],"dependencies":[]}]}

Rules:
- Extract ALL tasks from the Task Checklist section
- Each checkbox item becomes a task
- Set all statuses to "pending"
- Output ONLY the JSON object, nothing else

PRD content:
$mdContent
"@

    Write-RalphLog "Transforming markdown PRD with Claude..." -Level "INFO"

    try {
        $result = claude -p $transformPrompt --output-format json 2>&1

        # Parse the JSON response from Claude CLI
        $jsonContent = $result | Out-String

        # Claude CLI with --output-format json returns: {"type":"result","result":"...content..."}
        # The actual response is in the .result property as a string
        $cliResponse = $null
        try {
            $cliResponse = $jsonContent | ConvertFrom-Json
        } catch {
            Write-RalphLog "CLI response is not valid JSON, trying raw extraction" -Level "DEBUG"
        }

        $prdContent = $null
        if ($cliResponse -and $cliResponse.type -eq "result" -and $cliResponse.result) {
            # Extract the actual content from the CLI wrapper
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

function Update-TaskStatus {
    <#
    .SYNOPSIS
        Updates the status of a task in the PRD
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$TaskId,

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

    $task = $prd.tasks | Where-Object { $_.id -eq $TaskId }
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
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
            $listener.Start()
            $listener.Stop()
            return $port
        } catch {
            $port++
        }
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
                if ($Response) { $conversations[$i].response = $Response }
                if ($Status) { $conversations[$i].status = $Status }
                if ($ElapsedMinutes) { $conversations[$i].elapsedMinutes = $ElapsedMinutes }
                if ($Error) { $conversations[$i].error = $Error }
                $conversations[$i].completedAt = (Get-Date).ToString("o")
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

    # Check total runtime
    if ($state.startTime) {
        $startTime = [datetime]$state.startTime
        $runtime = ((Get-Date) - $startTime).TotalMinutes
        if ($runtime -ge $cb.maxTotalMinutes) {
            $result.Triggered = $true
            $result.Reason = "Maximum runtime of $($cb.maxTotalMinutes) minutes exceeded"
            return $result
        }
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
        'Invoke-Claude'
    )
}
