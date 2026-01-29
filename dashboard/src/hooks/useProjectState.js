import { useState, useEffect, useCallback } from 'react';
import {
  fetchProjectState,
  fetchProjectPrd,
  fetchProjectConfig,
  fetchProjectLogs,
  fetchRateLimit,
  fetchFileChanges
} from '../api';

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
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const refresh = useCallback(async () => {
    if (!port) return;

    try {
      const [stateData, prdData, configData, logsData, rateLimitData, changesData] = await Promise.all([
        fetchProjectState(port).catch(() => null),
        fetchProjectPrd(port).catch(() => null),
        fetchProjectConfig(port).catch(() => null),
        fetchProjectLogs(port, 50).catch(() => ({ lines: [] })),
        fetchRateLimit(port).catch(() => null),
        fetchFileChanges(port).catch(() => ({ filesChanged: [] }))
      ]);

      setState(stateData);
      setPrd(prdData);
      setConfig(configData);
      setLogs(logsData.lines || []);
      setRateLimit(rateLimitData);
      setChanges(changesData.filesChanged || []);
      setError(null);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
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
    loading,
    error,
    refresh
  };
}

export default useProjectState;
