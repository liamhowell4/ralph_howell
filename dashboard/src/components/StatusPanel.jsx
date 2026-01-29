import React from 'react';

function StatusPanel({ state }) {
  if (!state) {
    return (
      <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
        <h3 className="text-sm font-medium text-gray-400 mb-2">Status</h3>
        <p className="text-gray-500">No state available</p>
      </div>
    );
  }

  const { status, currentIteration, startTime, lastUpdateTime } = state;

  const statusColors = {
    running: 'text-green-400',
    paused: 'text-yellow-400',
    completed: 'text-blue-400',
    circuit_breaker: 'text-orange-400',
    max_iterations: 'text-purple-400',
    initialized: 'text-gray-400',
    error: 'text-red-400'
  };

  const formatTime = (isoString) => {
    if (!isoString) return 'N/A';
    const date = new Date(isoString);
    return date.toLocaleTimeString();
  };

  const formatDuration = (startIso) => {
    if (!startIso) return 'N/A';
    const start = new Date(startIso);
    const now = new Date();
    const diffMs = now - start;
    const minutes = Math.floor(diffMs / 60000);
    const hours = Math.floor(minutes / 60);

    if (hours > 0) {
      return `${hours}h ${minutes % 60}m`;
    }
    return `${minutes}m`;
  };

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

        <div className="flex items-center justify-between">
          <span className="text-gray-500">Runtime</span>
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
