/**
 * API client for Ralph Dashboard
 */

const MONITOR_URL = '/api';

/**
 * Fetch all registered projects
 */
export async function fetchProjects() {
  const res = await fetch(`${MONITOR_URL}/projects`);
  if (!res.ok) throw new Error('Failed to fetch projects');
  return res.json();
}

/**
 * Fetch project state
 */
export async function fetchProjectState(port) {
  const res = await fetch(`${MONITOR_URL}/projects/${port}/state`);
  if (!res.ok) throw new Error('Failed to fetch state');
  return res.json();
}

/**
 * Fetch project PRD
 */
export async function fetchProjectPrd(port) {
  const res = await fetch(`${MONITOR_URL}/projects/${port}/prd`);
  if (!res.ok) throw new Error('Failed to fetch PRD');
  return res.json();
}

/**
 * Fetch project logs
 */
export async function fetchProjectLogs(port, limit = 100) {
  const res = await fetch(`${MONITOR_URL}/projects/${port}/log?limit=${limit}`);
  if (!res.ok) throw new Error('Failed to fetch logs');
  return res.json();
}

/**
 * Fetch project config
 */
export async function fetchProjectConfig(port) {
  const res = await fetch(`${MONITOR_URL}/projects/${port}/config`);
  if (!res.ok) throw new Error('Failed to fetch config');
  return res.json();
}

/**
 * Update project config
 */
export async function updateProjectConfig(port, updates) {
  const res = await fetch(`${MONITOR_URL}/projects/${port}/config`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(updates)
  });
  if (!res.ok) throw new Error('Failed to update config');
  return res.json();
}

/**
 * Send stop signal to project
 */
export async function stopProject(port) {
  const res = await fetch(`${MONITOR_URL}/projects/${port}/stop`, {
    method: 'POST'
  });
  if (!res.ok) throw new Error('Failed to send stop signal');
  return res.json();
}

/**
 * Fetch rate limit info
 */
export async function fetchRateLimit(port) {
  const res = await fetch(`${MONITOR_URL}/projects/${port}/rate-limit`);
  if (!res.ok) throw new Error('Failed to fetch rate limit');
  return res.json();
}

/**
 * Fetch file changes
 */
export async function fetchFileChanges(port) {
  const res = await fetch(`${MONITOR_URL}/projects/${port}/changes`);
  if (!res.ok) throw new Error('Failed to fetch changes');
  return res.json();
}

/**
 * Fetch conversation log
 */
export async function fetchConversations(port, limit = 10) {
  const res = await fetch(`${MONITOR_URL}/projects/${port}/conversations?limit=${limit}`);
  if (!res.ok) throw new Error('Failed to fetch conversations');
  return res.json();
}
