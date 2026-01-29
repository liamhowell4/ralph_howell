import React from 'react';

function CircuitBreaker({ state, config }) {
  if (!state || !config) {
    return (
      <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
        <h3 className="text-sm font-medium text-gray-400 mb-2">Circuit Breaker</h3>
        <p className="text-gray-500">No data available</p>
      </div>
    );
  }

  const cb = config.circuitBreaker || {};
  const {
    noChangeCount = 0,
    sameErrorCount = 0,
    startTime
  } = state;

  const maxNoChange = cb.maxNoChangeIterations || 3;
  const maxSameError = cb.maxSameErrorIterations || 5;
  const maxMinutes = cb.maxTotalMinutes || 480;

  // Calculate runtime
  const runtimeMinutes = startTime
    ? Math.floor((new Date() - new Date(startTime)) / 60000)
    : 0;

  const metrics = [
    {
      label: 'No Change Iterations',
      current: noChangeCount,
      max: maxNoChange,
      danger: noChangeCount >= maxNoChange - 1
    },
    {
      label: 'Same Error Count',
      current: sameErrorCount,
      max: maxSameError,
      danger: sameErrorCount >= maxSameError - 1
    },
    {
      label: 'Runtime (minutes)',
      current: runtimeMinutes,
      max: maxMinutes,
      danger: runtimeMinutes >= maxMinutes * 0.9
    }
  ];

  const isTripped = state.status === 'circuit_breaker';

  return (
    <div className={`bg-gray-800 border rounded-lg p-4 ${isTripped ? 'border-orange-500' : 'border-gray-700'}`}>
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-medium text-gray-400">Circuit Breaker</h3>
        {isTripped && (
          <span className="px-2 py-0.5 bg-orange-900/50 text-orange-400 text-xs rounded">
            TRIPPED
          </span>
        )}
      </div>

      <div className="space-y-3">
        {metrics.map((metric, idx) => (
          <div key={idx}>
            <div className="flex justify-between text-sm mb-1">
              <span className="text-gray-500">{metric.label}</span>
              <span className={metric.danger ? 'text-orange-400' : 'text-white'}>
                {metric.current} / {metric.max}
              </span>
            </div>
            <div className="h-1.5 bg-gray-700 rounded-full overflow-hidden">
              <div
                className={`h-full transition-all duration-300 ${
                  metric.danger ? 'bg-orange-500' : 'bg-gray-500'
                }`}
                style={{ width: `${Math.min((metric.current / metric.max) * 100, 100)}%` }}
              />
            </div>
          </div>
        ))}
      </div>

      {state.lastError && (
        <div className="mt-3 p-2 bg-red-900/20 border border-red-800/50 rounded text-xs text-red-400 truncate" title={state.lastError}>
          Last error: {state.lastError}
        </div>
      )}
    </div>
  );
}

export default CircuitBreaker;
