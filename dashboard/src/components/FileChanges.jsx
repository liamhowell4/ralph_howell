import React from 'react';

function FileChanges({ changes }) {
  const getFileIcon = (path) => {
    const ext = path?.split('.').pop()?.toLowerCase();

    const icons = {
      js: 'text-yellow-400',
      jsx: 'text-cyan-400',
      ts: 'text-blue-400',
      tsx: 'text-blue-400',
      json: 'text-yellow-500',
      css: 'text-purple-400',
      html: 'text-orange-400',
      md: 'text-gray-400',
      ps1: 'text-blue-500',
      py: 'text-green-400'
    };

    return icons[ext] || 'text-gray-400';
  };

  return (
    <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-medium text-gray-400">File Changes</h3>
        <span className="text-xs text-gray-500">{changes?.length || 0} files</span>
      </div>

      <div className="h-64 overflow-y-auto">
        {(!changes || changes.length === 0) ? (
          <div className="text-gray-600 text-center py-4">No changes detected</div>
        ) : (
          <div className="space-y-1">
            {changes.map((file, idx) => (
              <div
                key={idx}
                className="flex items-center gap-2 p-2 rounded hover:bg-gray-700/50 font-mono text-sm"
              >
                <svg className={`w-4 h-4 ${getFileIcon(file)}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
                <span className="text-gray-300 truncate" title={file}>{file}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

export default FileChanges;
