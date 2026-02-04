/**
 * Ralph Monitor Dashboard Server
 * Runs on port 3500
 *
 * Provides:
 * - Project registry and discovery
 * - Proxy to per-project APIs
 * - Health monitoring
 */

import express from 'express';
import cors from 'cors';
import { createProxyMiddleware } from 'http-proxy-middleware';

const app = express();
const PORT = 3500;

// In-memory project registry
const projects = new Map();

// Middleware
app.use(cors());
app.use(express.json());

// Disable caching for all API responses
app.use((req, res, next) => {
  res.set({
    'Cache-Control': 'no-store, no-cache, must-revalidate, proxy-revalidate',
    'Pragma': 'no-cache',
    'Expires': '0'
  });
  next();
});

// Logging middleware
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  next();
});

/**
 * Health check endpoint
 */
app.get('/api/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'ralph-monitor',
    uptime: process.uptime(),
    projectCount: projects.size
  });
});

/**
 * List all registered projects with their health status
 */
app.get('/api/projects', async (req, res) => {
  const projectList = [];

  for (const [port, project] of projects) {
    // Check health of each project
    let isAlive = false;
    let projectState = null;

    try {
      const healthRes = await fetch(`http://localhost:${port}/api/health`, {
        signal: AbortSignal.timeout(2000)
      });
      if (healthRes.ok) {
        isAlive = true;
        const health = await healthRes.json();
        projectState = health.state;
      }
    } catch (e) {
      // Project is dead
      isAlive = false;
    }

    projectList.push({
      ...project,
      port,
      isAlive,
      state: projectState
    });
  }

  res.json(projectList);
});

/**
 * Register a new project
 */
app.post('/api/projects', (req, res) => {
  const { name, path, port } = req.body;

  if (!name || !path || !port) {
    return res.status(400).json({ error: 'Missing required fields: name, path, port' });
  }

  projects.set(port, {
    name,
    path,
    registeredAt: new Date().toISOString()
  });

  console.log(`Registered project: ${name} on port ${port}`);
  res.json({ success: true, port });
});

/**
 * Unregister a project
 */
app.delete('/api/projects/:port', (req, res) => {
  const port = parseInt(req.params.port);

  if (projects.has(port)) {
    const project = projects.get(port);
    projects.delete(port);
    console.log(`Unregistered project on port ${port}`);
    res.json({ success: true, project });
  } else {
    res.status(404).json({ error: 'Project not found' });
  }
});

/**
 * Proxy requests to per-project APIs
 * Routes: /api/projects/:port/*
 */
app.use('/api/projects/:port', (req, res, next) => {
  const port = parseInt(req.params.port);

  if (!projects.has(port)) {
    return res.status(404).json({ error: 'Project not found' });
  }

  // Create proxy middleware for this request
  const proxy = createProxyMiddleware({
    target: `http://localhost:${port}`,
    changeOrigin: true,
    pathRewrite: {
      [`^/api/projects/${port}`]: '/api'
    },
    onError: (err, req, res) => {
      console.error(`Proxy error for port ${port}:`, err.message);
      res.status(502).json({ error: 'Project API unavailable' });
    }
  });

  proxy(req, res, next);
});

/**
 * Cleanup dead projects periodically
 */
async function cleanupDeadProjects() {
  for (const [port, project] of projects) {
    try {
      const res = await fetch(`http://localhost:${port}/api/health`, {
        signal: AbortSignal.timeout(2000)
      });
      if (!res.ok) {
        throw new Error('Unhealthy');
      }
    } catch (e) {
      console.log(`Removing dead project on port ${port}: ${project.name}`);
      projects.delete(port);
    }
  }
}

// Run cleanup every 30 seconds
setInterval(cleanupDeadProjects, 30000);

// Start server
app.listen(PORT, () => {
  console.log(`
╭─────────────────────────────────────╮
│     Ralph Monitor Dashboard         │
│     Running on port ${PORT}            │
╰─────────────────────────────────────╯
  `);
});
