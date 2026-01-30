/**
 * Ralph Per-Project API Server
 * Runs on dynamic port (4001+)
 *
 * Usage: node project-api.js <project-path> <port>
 *
 * Provides:
 * - Health and status endpoints
 * - State and PRD access
 * - Log viewing
 * - Config management
 * - Stop signal
 */

import express from 'express';
import cors from 'cors';
import { readFileSync, writeFileSync, existsSync, statSync, renameSync } from 'fs';
import { join } from 'path';

// Parse arguments
const args = process.argv.slice(2);
if (args.length < 2) {
  console.error('Usage: node project-api.js <project-path> <port>');
  process.exit(1);
}

const PROJECT_PATH = args[0];
const PORT = parseInt(args[1]);
const RALPH_DIR = join(PROJECT_PATH, '.ralph');

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Helper functions
function readJsonFile(filename) {
  const filepath = join(RALPH_DIR, filename);
  if (!existsSync(filepath)) {
    return null;
  }
  try {
    const content = readFileSync(filepath, 'utf8');
    return JSON.parse(content);
  } catch (e) {
    console.error(`Error reading ${filename}:`, e.message);
    return null;
  }
}

function writeJsonFile(filename, data) {
  const filepath = join(RALPH_DIR, filename);
  const tempPath = `${filepath}.tmp`;
  try {
    writeFileSync(tempPath, JSON.stringify(data, null, 2));
    renameSync(tempPath, filepath);
    return true;
  } catch (e) {
    console.error(`Error writing ${filename}:`, e.message);
    return false;
  }
}

function readLogTail(lines = 100) {
  const filepath = join(RALPH_DIR, 'ralph.log');
  if (!existsSync(filepath)) {
    return [];
  }
  try {
    const content = readFileSync(filepath, 'utf8');
    const allLines = content.split('\n').filter(l => l.trim());
    return allLines.slice(-lines);
  } catch (e) {
    console.error('Error reading log:', e.message);
    return [];
  }
}

/**
 * Health check - source of truth for liveness
 */
app.get('/api/health', (req, res) => {
  const state = readJsonFile('state.json');

  res.json({
    status: 'healthy',
    service: 'ralph-project-api',
    projectPath: PROJECT_PATH,
    projectName: PROJECT_PATH.split(/[/\\]/).pop(),
    port: PORT,
    uptime: process.uptime(),
    state: state ? {
      status: state.status,
      currentIteration: state.currentIteration,
      lastUpdateTime: state.lastUpdateTime
    } : null
  });
});

/**
 * Full state
 */
app.get('/api/state', (req, res) => {
  const state = readJsonFile('state.json');
  if (!state) {
    return res.status(404).json({ error: 'State not found' });
  }
  res.json(state);
});

/**
 * PRD and task progress
 */
app.get('/api/prd', (req, res) => {
  const prd = readJsonFile('prd.json');
  if (!prd) {
    return res.status(404).json({ error: 'PRD not found' });
  }

  // Add progress calculation
  const tasks = prd.tasks || [];
  const completed = tasks.filter(t => t.status === 'completed').length;
  const inProgress = tasks.filter(t => t.status === 'in_progress').length;
  const blocked = tasks.filter(t => t.status === 'blocked').length;
  const pending = tasks.filter(t => t.status === 'pending').length;

  res.json({
    ...prd,
    progress: {
      total: tasks.length,
      completed,
      inProgress,
      blocked,
      pending,
      percentComplete: tasks.length > 0 ? Math.round((completed / tasks.length) * 100) : 0
    }
  });
});

/**
 * Log viewing with limit
 */
app.get('/api/log', (req, res) => {
  const limit = parseInt(req.query.limit) || 100;
  const lines = readLogTail(limit);
  res.json({ lines, count: lines.length });
});

/**
 * Get current config
 */
app.get('/api/config', (req, res) => {
  const config = readJsonFile('config.json');
  if (!config) {
    return res.status(404).json({ error: 'Config not found' });
  }
  res.json(config);
});

/**
 * Update config
 */
app.post('/api/config', async (req, res) => {
  const updates = req.body;

  if (!updates || typeof updates !== 'object') {
    return res.status(400).json({ error: 'Invalid config data' });
  }

  const config = readJsonFile('config.json') || {};

  // Deep merge updates
  function deepMerge(target, source) {
    for (const key of Object.keys(source)) {
      if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
        if (!target[key]) target[key] = {};
        deepMerge(target[key], source[key]);
      } else {
        target[key] = source[key];
      }
    }
    return target;
  }

  const merged = deepMerge(config, updates);

  // Write atomically
  const filepath = join(RALPH_DIR, 'config.json');
  const tempPath = `${filepath}.tmp`;

  try {
    writeFileSync(tempPath, JSON.stringify(merged, null, 2));
    renameSync(tempPath, filepath);
    res.json({ success: true, config: merged });
  } catch (e) {
    console.error('Error writing config:', e.message);
    res.status(500).json({ error: 'Failed to write config' });
  }
});

/**
 * Send stop signal
 */
app.post('/api/stop', (req, res) => {
  const signalPath = join(RALPH_DIR, 'stop.signal');

  try {
    writeFileSync(signalPath, 'STOP');
    res.json({ success: true, message: 'Stop signal sent' });
  } catch (e) {
    console.error('Error writing stop signal:', e.message);
    res.status(500).json({ error: 'Failed to send stop signal' });
  }
});

/**
 * Get file changes (from git - last commit + uncommitted)
 */
app.get('/api/changes', (req, res) => {
  const { execSync } = require('child_process');

  try {
    // Get files from the most recent commit
    let lastCommitFiles = [];
    try {
      const lastCommit = execSync('git diff-tree --no-commit-id --name-only -r HEAD', {
        cwd: PROJECT_PATH,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'] // Capture stderr to avoid shell redirection issues
      }).trim();
      if (lastCommit) {
        lastCommitFiles = lastCommit.split('\n').filter(f => f);
      }
    } catch (e) {
      // No commits yet or not a git repo
      console.log('Could not get last commit files:', e.message);
    }

    // Get currently uncommitted changes
    let uncommittedFiles = [];
    try {
      const status = execSync('git status --porcelain', {
        cwd: PROJECT_PATH,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe']
      }).trim();
      if (status) {
        uncommittedFiles = status.split('\n')
          .filter(line => line)
          .map(line => line.slice(3)); // Remove status prefix (e.g., " M ", "?? ")
      }
    } catch (e) {
      // Not a git repo
      console.log('Could not get uncommitted files:', e.message);
    }

    // Combine and dedupe
    const allFiles = [...new Set([...lastCommitFiles, ...uncommittedFiles])];

    console.log(`File changes: ${allFiles.length} files (${lastCommitFiles.length} from last commit, ${uncommittedFiles.length} uncommitted)`);

    res.json({
      filesChanged: allFiles,
      lastCommitFiles,
      uncommittedFiles
    });
  } catch (e) {
    console.error('Error getting file changes:', e.message);
    res.json({ filesChanged: [], lastCommitFiles: [], uncommittedFiles: [] });
  }
});

/**
 * Get conversation log (prompts and responses)
 */
app.get('/api/conversations', (req, res) => {
  const limit = parseInt(req.query.limit) || 10;
  const filepath = join(RALPH_DIR, 'conversations.json');

  if (!existsSync(filepath)) {
    return res.json({ conversations: [] });
  }

  try {
    const content = readFileSync(filepath, 'utf8');
    let conversations = JSON.parse(content);

    // Return most recent conversations
    if (conversations.length > limit) {
      conversations = conversations.slice(-limit);
    }

    // Reverse so most recent is first
    conversations = conversations.reverse();

    res.json({ conversations });
  } catch (e) {
    console.error('Error reading conversations:', e.message);
    res.json({ conversations: [] });
  }
});

/**
 * Get call timestamps for rate limit info
 */
app.get('/api/rate-limit', (req, res) => {
  const timestamps = readJsonFile('call_timestamps.json') || [];
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);

  const recentCalls = timestamps.filter(ts => new Date(ts) > oneHourAgo);
  const config = readJsonFile('config.json');
  const maxCalls = config?.rateLimiting?.maxCallsPerHour || 100;

  res.json({
    callsInLastHour: recentCalls.length,
    maxCallsPerHour: maxCalls,
    percentUsed: Math.round((recentCalls.length / maxCalls) * 100),
    timestamps: recentCalls
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`
╭─────────────────────────────────────╮
│     Ralph Project API               │
│     Port: ${PORT}                       │
│     Path: ${PROJECT_PATH.slice(0, 30)}...
╰─────────────────────────────────────╯
  `);
});
