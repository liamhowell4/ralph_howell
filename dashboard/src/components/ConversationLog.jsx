import React, { useState } from 'react';

function ConversationLog({ conversations }) {
  const [expandedId, setExpandedId] = useState(null);

  const statusColors = {
    running: 'bg-green-500',
    completed: 'bg-blue-500',
    timeout: 'bg-orange-500',
    error: 'bg-red-500'
  };

  const statusTextColors = {
    running: 'text-green-400',
    completed: 'text-blue-400',
    timeout: 'text-orange-400',
    error: 'text-red-400'
  };

  const formatTime = (isoString) => {
    if (!isoString) return '';
    const date = new Date(isoString);
    return date.toLocaleTimeString();
  };

  const truncateText = (text, maxLength = 150) => {
    if (!text) return '';
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength) + '...';
  };

  // Try to extract meaningful content from Claude's JSON response
  const parseResponse = (response) => {
    if (!response) return null;

    try {
      // Claude CLI returns JSON with result field
      const parsed = JSON.parse(response);
      if (parsed.result) {
        return parsed.result;
      }
      return response;
    } catch {
      return response;
    }
  };

  if (!conversations || conversations.length === 0) {
    return (
      <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
        <h3 className="text-sm font-medium text-gray-400 mb-3">Conversation Log</h3>
        <p className="text-gray-500 text-center py-4">No conversations yet</p>
      </div>
    );
  }

  return (
    <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-medium text-gray-400">Conversation Log</h3>
        <span className="text-xs text-gray-500">{conversations.length} entries</span>
      </div>

      <div className="space-y-3 max-h-96 overflow-y-auto">
        {conversations.map((conv) => {
          const isExpanded = expandedId === conv.id;
          const parsedResponse = parseResponse(conv.response);

          return (
            <div
              key={conv.id}
              className="border border-gray-700 rounded-lg overflow-hidden"
            >
              {/* Header */}
              <div
                className="flex items-center justify-between p-3 bg-gray-750 cursor-pointer hover:bg-gray-700 transition-colors"
                onClick={() => setExpandedId(isExpanded ? null : conv.id)}
              >
                <div className="flex items-center gap-3">
                  <div className={`w-2 h-2 rounded-full ${statusColors[conv.status] || 'bg-gray-500'}`} />
                  <div>
                    <div className="text-sm font-medium text-white">
                      Iteration {conv.iteration + 1}: Task {conv.taskId}
                    </div>
                    <div className="text-xs text-gray-400">{conv.taskTitle}</div>
                  </div>
                </div>

                <div className="flex items-center gap-3 text-xs">
                  <span className={statusTextColors[conv.status] || 'text-gray-400'}>
                    {conv.status}
                  </span>
                  {conv.elapsedMinutes > 0 && (
                    <span className="text-gray-500">{conv.elapsedMinutes}m</span>
                  )}
                  <span className="text-gray-500">{formatTime(conv.timestamp)}</span>
                  <svg
                    className={`w-4 h-4 text-gray-400 transition-transform ${isExpanded ? 'rotate-180' : ''}`}
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                  </svg>
                </div>
              </div>

              {/* Expanded content */}
              {isExpanded && (
                <div className="p-3 bg-gray-900 space-y-3">
                  {/* Prompt */}
                  <div>
                    <div className="text-xs font-medium text-purple-400 mb-1">Prompt</div>
                    <pre className="text-xs text-gray-300 bg-gray-800 p-2 rounded overflow-x-auto max-h-48 overflow-y-auto whitespace-pre-wrap">
                      {conv.prompt}
                    </pre>
                  </div>

                  {/* Response */}
                  {parsedResponse && (
                    <div>
                      <div className="text-xs font-medium text-green-400 mb-1">Response</div>
                      <pre className="text-xs text-gray-300 bg-gray-800 p-2 rounded overflow-x-auto max-h-64 overflow-y-auto whitespace-pre-wrap">
                        {parsedResponse}
                      </pre>
                    </div>
                  )}

                  {/* Error */}
                  {conv.error && (
                    <div>
                      <div className="text-xs font-medium text-red-400 mb-1">Error</div>
                      <pre className="text-xs text-red-300 bg-red-900/20 p-2 rounded overflow-x-auto">
                        {conv.error}
                      </pre>
                    </div>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default ConversationLog;
