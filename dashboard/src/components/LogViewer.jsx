import React, { useRef, useEffect } from 'react';

function LogViewer({ logs }) {
  const containerRef = useRef(null);

  // Auto-scroll to bottom when new logs arrive
  useEffect(() => {
    if (containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [logs]);

  const parseLogLine = (line) => {
    // Parse: [2024-01-15 10:30:45] [INFO] Message
    const match = line.match(/^\[([\d-\s:]+)\]\s*\[(\w+)\]\s*(.*)$/);
    if (match) {
      return {
        timestamp: match[1],
        level: match[2],
        message: match[3]
      };
    }
    return { timestamp: '', level: '', message: line };
  };

  const getLevelColor = (level) => {
    switch (level?.toUpperCase()) {
      case 'ERROR': return 'text-red-400';
      case 'WARN': return 'text-yellow-400';
      case 'INFO': return 'text-blue-400';
      case 'DEBUG': return 'text-gray-500';
      default: return 'text-gray-400';
    }
  };

  return (
    <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-medium text-gray-400">Logs</h3>
        <span className="text-xs text-gray-500">{logs?.length || 0} lines</span>
      </div>

      <div
        ref={containerRef}
        className="h-64 overflow-y-auto bg-gray-900 rounded p-2 font-mono text-xs"
      >
        {(!logs || logs.length === 0) ? (
          <div className="text-gray-600 text-center py-4">No logs yet</div>
        ) : (
          logs.map((line, idx) => {
            const parsed = parseLogLine(line);
            return (
              <div key={idx} className="py-0.5 hover:bg-gray-800/50">
                <span className="text-gray-600">{parsed.timestamp}</span>
                {parsed.level && (
                  <span className={`ml-2 ${getLevelColor(parsed.level)}`}>
                    [{parsed.level}]
                  </span>
                )}
                <span className="ml-2 text-gray-300">{parsed.message}</span>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}

export default LogViewer;
