import React, { useState, useEffect } from 'react';

function StatusPanel({ state, config }) {
  const [now, setNow] = useState(new Date());

  // Update "now" every second for live elapsed time
  useEffect(() => {
    const interval = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(interval);
  }, []);

  if (!state) {
    return (
      <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
        <h3 className="text-sm font-medium text-gray-400 mb-2">Status</h3>
        <p className="text-gray-500">No state available</p>
      </div>
    );
  }

  const {
    status,
    currentIteration,
    startTime,
    lastUpdateTime,
    iterationStartTime,
    iterationStatus,
    iterationElapsedMinutes
  } = state;

  const timeoutMinutes = config?.iterationTimeoutMinutes || 15;

  const statusColors = {
    running: 'text-green-400',
    paused: 'text-yellow-400',
    completed: 'text-blue-400',
    circuit_breaker: 'text-orange-400',
    max_iterations: 'text-purple-400',
    initialized: 'text-gray-400',
    error: 'text-red-400',
    timeout: 'text-red-400'
  };

  const iterationStatusColors = {
    running: 'text-green-400',
    completed: 'text-blue-400',
    timeout: 'text-red-400',
    error: 'text-red-400',
    interrupted: 'text-yellow-400'
  };

  const formatTime = (isoString) => {
    if (!isoString) return 'N/A';
    const date = new Date(isoString);
    return date.toLocaleTimeString();
  };

  const formatDuration = (startIso) => {
    if (!startIso) return 'N/A';
    const start = new Date(startIso);
    const diffMs = now - start;
    const minutes = Math.floor(diffMs / 60000);
    const hours = Math.floor(minutes / 60);

    if (hours > 0) {
      return `${hours}h ${minutes % 60}m`;
    }
    return `${minutes}m`;
  };

  // Calculate live iteration elapsed time
  const getIterationElapsed = () => {
    if (!iterationStartTime) return null;
    if (iterationStatus !== 'running') {
      // Use stored value if iteration is not running
      return iterationElapsedMinutes || 0;
    }
    // Calculate live elapsed time
    const start = new Date(iterationStartTime);
    const diffMs = now - start;
    return Math.round(diffMs / 60000 * 10) / 10; // 1 decimal place
  };

  const iterationElapsed = getIterationElapsed();
  const isNearTimeout = iterationElapsed && iterationStatus === 'running' && iterationElapsed >= timeoutMinutes * 0.8;
  const iterationProgress = iterationElapsed ? Math.min((iterationElapsed / timeoutMinutes) * 100, 100) : 0;

  return (
    <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
      <h3 className="text-sm font-medium text-gray-400 mb-3">Status</h3>

      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <span className="text-gray-500">State</span>
          <span className={`font-semibold capitalize ${statusColors[status] || 'text-gray-400'}`}>
            {status?.replace('_', ' ')}
          </span>
        </div>

        <div className="flex items-center justify-between">
          <span className="text-gray-500">Iteration</span>
          <span className="text-white font-mono">{currentIteration || 0}</span>
        </div>

        {(config?.model || config?.engine) && (
          <div className="flex items-center justify-between">
            <span className="text-gray-500">Model</span>
            <span className="text-white text-sm truncate ml-2" title={`${config.engine || ''} / ${config.model || ''}`}>
              {config.engine && config.engine !== 'claude'
                ? config.engine
                : config.model
                  ? config.model.replace(/^claude-/, '').replace(/-\d{8}$/, '')
                  : config.engine}
            </span>
          </div>
        )}

        {/* Iteration timing - only show when there's an active/recent iteration */}
        {iterationStartTime && (
          <div className="pt-2 border-t border-gray-700">
            <div className="flex items-center justify-between mb-2">
              <span className="text-gray-500">Iteration Status</span>
              <span className={`font-medium capitalize ${iterationStatusColors[iterationStatus] || 'text-gray-400'}`}>
                {iterationStatus === 'running' && (
                  <span className="inline-block w-2 h-2 bg-green-400 rounded-full mr-2 animate-pulse" />
                )}
                {iterationStatus || 'unknown'}
              </span>
            </div>

            <div className="flex items-center justify-between mb-1">
              <span className="text-gray-500">Iteration Time</span>
              <span className={`font-mono ${isNearTimeout ? 'text-orange-400' : 'text-white'}`}>
                {iterationElapsed !== null ? `${iterationElapsed}m` : 'N/A'}
                <span className="text-gray-500 text-xs ml-1">/ {timeoutMinutes}m</span>
              </span>
            </div>

            {/* Progress bar for iteration timeout */}
            {iterationStatus === 'running' && (
              <div className="w-full bg-gray-700 rounded-full h-1.5 mt-1">
                <div
                  className={`h-1.5 rounded-full transition-all duration-500 ${
                    isNearTimeout ? 'bg-orange-400' : 'bg-green-400'
                  }`}
                  style={{ width: `${iterationProgress}%` }}
                />
              </div>
            )}
          </div>
        )}

        <div className="flex items-center justify-between">
          <span className="text-gray-500">Total Runtime</span>
          <span className="text-white">{formatDuration(startTime)}</span>
        </div>

        <div className="flex items-center justify-between">
          <span className="text-gray-500">Last Update</span>
          <span className="text-white text-sm">{formatTime(lastUpdateTime)}</span>
        </div>
      </div>
    </div>
  );
}

export default StatusPanel;
