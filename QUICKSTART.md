# Ralph Howell Loop - Quick Start Guide

## Setup Complete!

The following has been configured:

| What | Where |
|------|-------|
| Batch files | `C:\Users\E707254\bin\` |
| PowerShell aliases | Your PowerShell profile |
| PATH updated | `C:\Users\E707254\bin` added |

**Restart your terminal** for PATH changes to take effect.

---

## Usage

### From Any Folder

**Command Prompt or PowerShell:**
```cmd
ralph                              # Interactive mode
ralph --from-md                    # Use PROMPT.md in current folder
ralph --from-md --prd-path ".\my.md"   # Use specific markdown file
ralph --resume                     # Resume paused session
ralph --dry-run                    # Preview without running
ralph --help                       # Show all options
```

**Start the Dashboard:**
```cmd
ralph-dashboard
```
Then open http://localhost:5173

---

## What You Need in Your Project

Create a `PROMPT.md` file describing what you want built. Example:

```markdown
# My Project

Build a REST API with the following endpoints:

## Tasks
1. Set up Express server
2. Create /users endpoint
3. Add authentication
4. Write tests
```

Ralph will transform this into tasks and work through them autonomously.

---

## Commands Reference

| Command | Description |
|---------|-------------|
| `ralph` | Interactive setup |
| `ralph --from-md` | Transform PROMPT.md and start |
| `ralph --from-json --prd-path ".\prd.json"` | Use existing PRD |
| `ralph --resume` | Continue paused session |
| `ralph --reinit` | Start fresh (overwrites .ralph/) |
| `ralph --dry-run` | Preview only |
| `ralph --help` | Show all options |
| `ralph-dashboard` | Launch monitoring dashboard |

---

## Files Created in Your Project

When you run Ralph, it creates a `.ralph/` folder:

```
your-project/
├── .ralph/
│   ├── config.json      # Settings (editable)
│   ├── state.json       # Current progress
│   ├── prd.json         # Tasks extracted from PROMPT.md
│   ├── ralph.log        # Activity log
│   └── call_timestamps.json
└── PROMPT.md            # Your input
```

---

## Configuration

Edit `.ralph/config.json` to customize:

```json
{
  "model": "claude-opus-4-5-20250514",
  "maxIterations": 50,
  "rateLimiting": {
    "maxCallsPerHour": 100
  },
  "circuitBreaker": {
    "maxNoChangeIterations": 3
  },
  "git": {
    "autoCommit": true
  }
}
```

Changes take effect on the next iteration (no restart needed).

---

## Stopping & Resuming

- **Ctrl+C** - Pauses the loop, saves state
- **`ralph -Resume`** - Continues where you left off
- **Dashboard Stop button** - Sends stop signal

---

## Troubleshooting

**"ralph" is not recognized:**
- Restart your terminal (PATH needs to reload)

**Dashboard not showing projects:**
- Make sure `ralph-dashboard` is running
- Check http://localhost:3500/api/health

**Loop stuck:**
- Check `.ralph/ralph.log` for errors
- Try `ralph -Resume` after fixing issues

---

## Locations

- Scripts: `C:\Users\E707254\coding_projects_local\ralph_howell\ralph-loop-system\scripts\`
- Dashboard: `C:\Users\E707254\coding_projects_local\ralph_howell\ralph-loop-system\dashboard\`
- Batch files: `C:\Users\E707254\bin\`
