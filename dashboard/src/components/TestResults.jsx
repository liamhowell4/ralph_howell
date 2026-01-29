import React from 'react';

function TestResults({ results }) {
  if (!results) {
    return (
      <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
        <h3 className="text-sm font-medium text-gray-400 mb-2">Test Results</h3>
        <p className="text-gray-500">No test results available</p>
      </div>
    );
  }

  const { passed = 0, failed = 0, skipped = 0, total = 0 } = results;
  const passRate = total > 0 ? Math.round((passed / total) * 100) : 0;

  return (
    <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-medium text-gray-400">Test Results</h3>
        <span className={`text-sm font-medium ${passRate === 100 ? 'text-green-400' : passRate > 50 ? 'text-yellow-400' : 'text-red-400'}`}>
          {passRate}% passing
        </span>
      </div>

      {/* Summary bar */}
      <div className="h-3 bg-gray-700 rounded-full overflow-hidden flex">
        {passed > 0 && (
          <div
            className="bg-green-500 h-full"
            style={{ width: `${(passed / total) * 100}%` }}
          />
        )}
        {failed > 0 && (
          <div
            className="bg-red-500 h-full"
            style={{ width: `${(failed / total) * 100}%` }}
          />
        )}
        {skipped > 0 && (
          <div
            className="bg-gray-500 h-full"
            style={{ width: `${(skipped / total) * 100}%` }}
          />
        )}
      </div>

      {/* Legend */}
      <div className="flex gap-4 mt-3 text-sm">
        <div className="flex items-center gap-1">
          <div className="w-3 h-3 bg-green-500 rounded" />
          <span className="text-gray-400">{passed} passed</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-3 h-3 bg-red-500 rounded" />
          <span className="text-gray-400">{failed} failed</span>
        </div>
        {skipped > 0 && (
          <div className="flex items-center gap-1">
            <div className="w-3 h-3 bg-gray-500 rounded" />
            <span className="text-gray-400">{skipped} skipped</span>
          </div>
        )}
      </div>

      {/* Failed tests */}
      {results.failures && results.failures.length > 0 && (
        <div className="mt-4 pt-3 border-t border-gray-700">
          <h4 className="text-xs font-medium text-red-400 mb-2">Failed Tests</h4>
          <div className="space-y-1">
            {results.failures.slice(0, 5).map((failure, idx) => (
              <div key={idx} className="text-xs text-gray-400 truncate" title={failure}>
                {failure}
              </div>
            ))}
            {results.failures.length > 5 && (
              <div className="text-xs text-gray-500">
                +{results.failures.length - 5} more
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export default TestResults;
