# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Ralph Howell Loop is an autonomous development loop system for Claude Code. It executes development tasks iteratively using PowerShell scripts, with a React dashboard for monitoring multiple projects.

## Commands

### Running the Loop

```bash
# Interactive mode
ralph

# Transform markdown PRD and start
ralph --from-md --prd-path ".\PROMPT.md"

# Resume paused session
ralph --resume

# Dry run (preview without executing)
ralph --dry-run

# Show help
ralph --help
```

Or invoke the PowerShell script directly:
```powershell
.\scripts\ralph.ps1 -FromMd -PrdPath ".\PROMPT.md"
```

### Dashboard

```powershell
# Start dashboard (monitor server + React UI)
.\scripts\ralph-monitor.ps1

# Or manually:
cd dashboard
npm install
npm run start
```

Dashboard runs on:
- Monitor API: http://localhost:3500
- React UI: http://localhost:5173

### Testing

```powershell
# Run Pester tests
Invoke-Pester .\tests\utils.tests.ps1 -Output Detailed
```

## Architecture

### PowerShell Scripts (`scripts/`)

- **ralph.ps1**: Main entry point. Handles CLI args, interactive menu, orchestrates the loop, manages API processes, and cleanup on Ctrl+C.
- **utils.ps1**: Shared utilities including logging, state management, config handling, git operations, signal parsing, rate limiting, and circuit breaker logic.
- **ralph-monitor.ps1**: Launches the dashboard server and React dev server.

### Dashboard (`dashboard/`)

Two-tier server architecture:
- **server/index.js** (Port 3500): Central monitor server. Maintains in-memory project registry, proxies requests to per-project APIs, performs health checks and cleanup of dead projects.
- **server/project-api.js** (Ports 4001+): Per-project API spawned by the loop. Reads/writes `.ralph/` files, exposes state, PRD, logs, config, and stop signal endpoints.

React frontend in `src/` uses Vite + Tailwind.

### Per-Project State (`.ralph/` directory)

When Ralph runs in a project, it creates:
- `config.json` - Settings (hot-reloadable)
- `state.json` - Current iteration, status, timestamps
- `prd.json` - Tasks extracted from markdown PRD
- `ralph.log` - Activity log
- `call_timestamps.json` - Rate limiting data
- `stop.signal` - Stop signal file (created by dashboard)

## Signal Protocol

Claude must include completion signals in responses:
```
<PROMISE>COMPLETE</PROMISE>  - Task completed
<PROMISE>BLOCKED</PROMISE>   - Task blocked, needs intervention
```

For blocked tasks:
```
<BLOCKER>Reason why task cannot proceed</BLOCKER>
```

## Key Configuration

Default config in `utils.ps1:$script:DefaultConfig`:
- Model: `claude-opus-4-5-20251101`
- Max iterations: 50
- Rate limiting: 100 calls/hour, 10s cooldown
- Circuit breaker: stops after 3 no-change iterations, 5 same-error iterations, or 480 minutes total

## Circuit Breaker Conditions

Loop auto-stops when:
1. No git changes for N consecutive iterations (default: 3)
2. Same error occurs N times in a row (default: 5)
3. Total runtime exceeds N minutes (default: 480)
