import { useState, useEffect, useCallback, useRef } from 'react';
import {
  fetchProjectState,
  fetchProjectPrd,
  fetchProjectConfig,
  fetchProjectLogs,
  fetchRateLimit,
  fetchFileChanges,
  fetchConversations
} from '../api';

/**
 * Fetch with timeout wrapper
 */
function withTimeout(promise, ms = 5000) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error('Request timeout')), ms)
    )
  ]);
}

/**
 * Hook for fetching and managing project state
 * @param {number} port - Project API port
 * @param {number} pollInterval - Polling interval in ms
 */
export function useProjectState(port, pollInterval = 3000) {
  const [state, setState] = useState(null);
  const [prd, setPrd] = useState(null);
  const [config, setConfig] = useState(null);
  const [logs, setLogs] = useState([]);
  const [rateLimit, setRateLimit] = useState(null);
  const [changes, setChanges] = useState([]);
  const [conversations, setConversations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const isFetching = useRef(false);
  const failureCount = useRef(0);

  const refresh = useCallback(async () => {
    if (!port) return;

    // Prevent concurrent fetches that could cause race conditions
    if (isFetching.current) return;
    isFetching.current = true;

    try {
      const [stateData, prdData, configData, logsData, rateLimitData, changesData, conversationsData] = await Promise.all([
        withTimeout(fetchProjectState(port)).catch(() => null),
        withTimeout(fetchProjectPrd(port)).catch(() => null),
        withTimeout(fetchProjectConfig(port)).catch(() => null),
        withTimeout(fetchProjectLogs(port, 50)).catch(() => ({ lines: [] })),
        withTimeout(fetchRateLimit(port)).catch(() => null),
        withTimeout(fetchFileChanges(port)).catch(() => ({ filesChanged: [] })),
        withTimeout(fetchConversations(port, 10)).catch(() => ({ conversations: [] }))
      ]);

      // Only update state if we got valid data
      if (stateData) setState(stateData);
      if (prdData) setPrd(prdData);
      if (configData) setConfig(configData);
      setLogs(logsData?.lines || []);
      if (rateLimitData) setRateLimit(rateLimitData);
      setChanges(changesData?.filesChanged || []);
      setConversations(conversationsData?.conversations || []);

      // Clear error on success and reset failure count
      setError(null);
      failureCount.current = 0;
    } catch (e) {
      failureCount.current++;
      // Only set error after multiple failures to avoid flicker
      if (failureCount.current >= 3) {
        setError(e.message);
      }
    } finally {
      setLoading(false);
      isFetching.current = false;
    }
  }, [port]);

  useEffect(() => {
    if (!port) return;

    refresh();
    const intervalId = setInterval(refresh, pollInterval);
    return () => clearInterval(intervalId);
  }, [port, pollInterval, refresh]);

  return {
    state,
    prd,
    config,
    logs,
    rateLimit,
    changes,
    conversations,
    loading,
    error,
    refresh
  };
}

export default useProjectState;
