import { useState, useEffect, useCallback, useRef } from 'react';

/**
 * Hook for polling data at regular intervals
 * @param {Function} fetchFn - Async function to fetch data
 * @param {number} interval - Polling interval in ms (default 3000)
 * @param {boolean} enabled - Whether polling is enabled
 */
export function usePolling(fetchFn, interval = 3000, enabled = true) {
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(true);
  const fetchFnRef = useRef(fetchFn);

  // Keep fetchFn ref up to date
  useEffect(() => {
    fetchFnRef.current = fetchFn;
  }, [fetchFn]);

  const refresh = useCallback(async () => {
    try {
      const result = await fetchFnRef.current();
      setData(result);
      setError(null);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!enabled) return;

    // Initial fetch
    refresh();

    // Set up polling
    const intervalId = setInterval(refresh, interval);

    return () => clearInterval(intervalId);
  }, [interval, enabled, refresh]);

  return { data, error, loading, refresh };
}

export default usePolling;
