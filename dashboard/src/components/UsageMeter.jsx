import React from 'react';

function UsageMeter({ rateLimit }) {
  if (!rateLimit) {
    return (
      <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
        <h3 className="text-sm font-medium text-gray-400 mb-2">API Usage</h3>
        <p className="text-gray-500">No rate limit data</p>
      </div>
    );
  }

  const { callsInLastHour, maxCallsPerHour, percentUsed } = rateLimit;

  const getColor = (percent) => {
    if (percent >= 90) return 'from-red-500 to-red-600';
    if (percent >= 70) return 'from-yellow-500 to-orange-500';
    return 'from-green-500 to-emerald-500';
  };

  const getTextColor = (percent) => {
    if (percent >= 90) return 'text-red-400';
    if (percent >= 70) return 'text-yellow-400';
    return 'text-green-400';
  };

  return (
    <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
      <h3 className="text-sm font-medium text-gray-400 mb-3">API Usage (1h)</h3>

      {/* Circular progress */}
      <div className="flex items-center gap-4">
        <div className="relative w-16 h-16">
          <svg className="w-16 h-16 transform -rotate-90">
            {/* Background circle */}
            <circle
              cx="32"
              cy="32"
              r="28"
              stroke="currentColor"
              strokeWidth="6"
              fill="none"
              className="text-gray-700"
            />
            {/* Progress circle */}
            <circle
              cx="32"
              cy="32"
              r="28"
              stroke="url(#gradient)"
              strokeWidth="6"
              fill="none"
              strokeLinecap="round"
              strokeDasharray={`${percentUsed * 1.76} 176`}
              className="transition-all duration-500"
            />
            <defs>
              <linearGradient id="gradient" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" className={percentUsed >= 90 ? 'text-red-500' : percentUsed >= 70 ? 'text-yellow-500' : 'text-green-500'} stopColor="currentColor" />
                <stop offset="100%" className={percentUsed >= 90 ? 'text-red-600' : percentUsed >= 70 ? 'text-orange-500' : 'text-emerald-500'} stopColor="currentColor" />
              </linearGradient>
            </defs>
          </svg>
          <span className={`absolute inset-0 flex items-center justify-center text-lg font-bold ${getTextColor(percentUsed)}`}>
            {percentUsed}%
          </span>
        </div>

        <div className="flex-1">
          <div className="text-2xl font-bold text-white">
            {callsInLastHour}
            <span className="text-sm text-gray-500 font-normal ml-1">/ {maxCallsPerHour}</span>
          </div>
          <div className="text-sm text-gray-500">calls this hour</div>
        </div>
      </div>

      {/* Warning message */}
      {percentUsed >= 90 && (
        <div className="mt-3 p-2 bg-red-900/30 border border-red-800 rounded text-sm text-red-400">
          Rate limit almost reached! Loop may pause soon.
        </div>
      )}
    </div>
  );
}

export default UsageMeter;
