# Ralph Howell Loop

An autonomous development loop system for Claude Code with PowerShell scripts and a React dashboard for monitoring.

*Named in honor of creating something that just keeps going.*

## Features

- **Autonomous Loop**: Executes development tasks iteratively using Claude Code
- **PRD Transformation**: Converts markdown PRDs to structured JSON tasks
- **Rate Limiting**: Sliding window rate limiter to prevent API overuse
- **Circuit Breaker**: Automatic stop conditions for runaway loops
- **Real-time Dashboard**: Monitor multiple projects from a single interface
- **Config Hot-Reload**: Edit configuration while loop is running

## Quick Start

### 1. Start a Loop from Markdown PRD

```powershell
cd your-project-directory
.\path\to\ralph-loop-system\scripts\ralph.ps1 -FromMd -PrdPath ".\PROMPT.md"
```

### 2. Interactive Mode

```powershell
.\scripts\ralph.ps1
```

### 3. Resume Paused Session

```powershell
.\scripts\ralph.ps1 -Resume
```

## Directory Structure

```
ralph-loop-system/
├── scripts/
│   ├── utils.ps1              # Shared utilities
│   ├── ralph.ps1              # Main entry point
│   └── ralph-monitor.ps1      # Dashboard launcher
├── dashboard/
│   ├── server/
│   │   ├── index.js           # Monitor server (port 3500)
│   │   └── project-api.js     # Per-project API (ports 4001+)
│   └── src/                   # React dashboard
└── tests/
    └── utils.tests.ps1        # Pester tests
```

## Command Line Options

| Flag | Description |
|------|-------------|
| `-FromMd` | Transform a markdown PRD file |
| `-FromJson` | Use an existing prd.json file |
| `-PrdPath <path>` | Path to PRD file |
| `-Resume` | Resume a paused session |
| `-Reinit` | Force reinitialize |
| `-MaxIterations <n>` | Override max iterations |
| `-Engine <name>` | Select AI engine: `claude`, `codex`, or `opencode` |
| `-Codex` | Shorthand for `-Engine codex` |
| `-OpenCode` | Shorthand for `-Engine opencode` |
| `-DryRun` | Preview without executing |

## Engine Selection

Ralph supports multiple AI engines. Use flags or set `"engine"` in config:

```powershell
# Claude (default)
ralph --from-md --prd-path .\PROMPT.md

# OpenAI Codex
ralph --from-md --prd-path .\PROMPT.md --codex

# OpenCode
ralph --from-md --prd-path .\PROMPT.md --opencode
```

| Engine | CLI | Notes |
|--------|-----|-------|
| Claude | `claude` | Default. Uses `--model`, `--max-turns` |
| Codex | `codex` | Uses `codex exec`. Model set via Codex config |
| OpenCode | `opencode` | Uses `opencode run`. Model set via OpenCode config |

## Configuration

Configuration is stored in `.ralph/config.json`:

```json
{
  "engine": "claude",
  "model": "claude-opus-4-5-20250514",
  "maxIterations": 50,
  "maxTurnsPerIteration": 50,
  "rateLimiting": {
    "maxCallsPerHour": 100,
    "cooldownSeconds": 10,
    "retryCount": 1
  },
  "circuitBreaker": {
    "maxNoChangeIterations": 3,
    "maxSameErrorIterations": 5,
    "maxTotalMinutes": 480
  },
  "git": {
    "autoCommit": true,
    "autoInit": true,
    "commitMessagePrefix": "Ralph iteration"
  },
  "dashboard": {
    "enabled": true
  }
}
```

## Signal Protocol

Claude must include one of these signals in its response to indicate task status:

```
<PROMISE>COMPLETE</PROMISE>  - Task completed successfully
<PROMISE>BLOCKED</PROMISE>   - Task blocked, needs intervention
```

For blocked tasks, include a blocker reason:
```
<BLOCKER>Reason why the task cannot proceed</BLOCKER>
```

## Dashboard

### Start the Dashboard

```powershell
.\scripts\ralph-monitor.ps1
```

Or manually:

```bash
cd dashboard
npm install
npm run start
```

### Dashboard URLs

- **Monitor API**: http://localhost:3500
- **Dashboard UI**: http://localhost:5173

### API Endpoints

#### Monitor (Port 3500)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check |
| `/api/projects` | GET | List all projects |
| `/api/projects` | POST | Register project |
| `/api/projects/:port/*` | ALL | Proxy to project API |

#### Per-Project (Ports 4001+)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Liveness check |
| `/api/state` | GET | Full state |
| `/api/prd` | GET | Tasks and progress |
| `/api/log?limit=N` | GET | Log lines |
| `/api/config` | GET/POST | Read/update config |
| `/api/stop` | POST | Send stop signal |

## Testing

Run Pester tests:

```powershell
cd ralph-loop-system
Invoke-Pester .\tests\utils.tests.ps1 -Output Detailed
```

## Circuit Breaker Conditions

The loop automatically stops when:

1. **No changes** for N consecutive iterations (default: 3)
2. **Same error** occurs N times in a row (default: 5)
3. **Total runtime** exceeds N minutes (default: 480)

## Requirements

- PowerShell 5.1 or later
- Node.js 18 or later
- At least one AI CLI:
  - Claude Code CLI (`claude`) - default
  - OpenAI Codex CLI (`codex`) - optional
  - OpenCode CLI (`opencode`) - optional

## Troubleshooting

### Loop not starting
- Check if `claude` CLI is installed and accessible
- Verify PRD file exists and is valid

### Dashboard not showing projects
- Ensure monitor server is running on port 3500
- Check that project API started (look for port in logs)

### Rate limit hit
- Wait for oldest call to age out (shown in logs)
- Reduce `maxCallsPerHour` in config

### Circuit breaker triggered
- Check logs for repeated errors
- Review task definitions for clarity
- Manually intervene and resume

## License

MIT
