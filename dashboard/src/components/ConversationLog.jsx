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

  // Extract completion signal from response
  const extractSignal = (response) => {
    if (!response) return null;
    if (response.includes('<PROMISE>COMPLETE</PROMISE>')) return 'COMPLETE';
    if (response.includes('<PROMISE>BLOCKED</PROMISE>')) return 'BLOCKED';
    return null;
  };

  // Extract blocker reason
  const extractBlocker = (response) => {
    if (!response) return null;
    const match = response.match(/<BLOCKER>([\s\S]*?)<\/BLOCKER>/);
    return match ? match[1].trim() : null;
  };

  // Extract summary of actions from response
  const extractSummary = (response) => {
    if (!response) return [];
    const actions = [];

    // Common patterns for file operations
    const filePatterns = [
      /(?:created|wrote|added)\s+(?:file\s+)?[`"']?([^\s`"']+\.[a-z]+)[`"']?/gi,
      /(?:modified|edited|updated)\s+(?:file\s+)?[`"']?([^\s`"']+\.[a-z]+)[`"']?/gi,
      /(?:deleted|removed)\s+(?:file\s+)?[`"']?([^\s`"']+\.[a-z]+)[`"']?/gi,
    ];

    // Common patterns for actions
    const actionPatterns = [
      /(?:implemented|added|created)\s+([^.!?\n]{10,60})/gi,
      /(?:fixed|resolved)\s+([^.!?\n]{10,60})/gi,
      /(?:updated|modified|changed)\s+([^.!?\n]{10,60})/gi,
      /(?:ran|executed)\s+(?:tests?|npm|yarn|pnpm)([^.!?\n]{0,40})/gi,
    ];

    // Extract file operations
    filePatterns.forEach(pattern => {
      let match;
      while ((match = pattern.exec(response)) !== null) {
        const action = match[0].substring(0, 80);
        if (!actions.includes(action)) {
          actions.push(action);
        }
      }
    });

    // Extract general actions (limit to first few)
    actionPatterns.forEach(pattern => {
      let match;
      while ((match = pattern.exec(response)) !== null && actions.length < 5) {
        const action = match[0].substring(0, 80);
        if (!actions.some(a => a.toLowerCase() === action.toLowerCase())) {
          actions.push(action);
        }
      }
    });

    return actions.slice(0, 5);
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

  // Signal badge component
  const SignalBadge = ({ signal }) => {
    if (!signal) return null;

    const isComplete = signal === 'COMPLETE';
    return (
      <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium ${
        isComplete
          ? 'bg-green-900/50 text-green-400 border border-green-700'
          : 'bg-orange-900/50 text-orange-400 border border-orange-700'
      }`}>
        {isComplete ? (
          <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
        ) : (
          <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
        )}
        {signal}
      </span>
    );
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
          const signal = extractSignal(parsedResponse);
          const blocker = extractBlocker(parsedResponse);
          const summary = extractSummary(parsedResponse);

          return (
            <div
              key={conv.id}
              className={`border rounded-lg overflow-hidden ${
                signal === 'COMPLETE' ? 'border-green-700/50' :
                signal === 'BLOCKED' ? 'border-orange-700/50' :
                'border-gray-700'
              }`}
            >
              {/* Header */}
              <div
                className={`flex items-center justify-between p-3 cursor-pointer hover:bg-gray-700 transition-colors ${
                  signal === 'COMPLETE' ? 'bg-green-900/10' :
                  signal === 'BLOCKED' ? 'bg-orange-900/10' :
                  'bg-gray-750'
                }`}
                onClick={() => setExpandedId(isExpanded ? null : conv.id)}
              >
                <div className="flex items-center gap-3">
                  <div className={`w-2 h-2 rounded-full ${statusColors[conv.status] || 'bg-gray-500'}`} />
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium text-white">
                        Iteration {conv.iteration + 1}: Task {conv.taskId}
                      </span>
                      <SignalBadge signal={signal} />
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

              {/* Summary section (always visible when collapsed) */}
              {!isExpanded && (summary.length > 0 || blocker) && (
                <div className="px-3 py-2 bg-gray-850 border-t border-gray-700/50">
                  {blocker && (
                    <div className="flex items-start gap-2 text-xs text-orange-400 mb-1">
                      <svg className="w-3.5 h-3.5 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                      </svg>
                      <span className="line-clamp-2">{truncateText(blocker, 120)}</span>
                    </div>
                  )}
                  {summary.length > 0 && (
                    <div className="text-xs text-gray-400">
                      {summary.slice(0, 2).map((action, i) => (
                        <div key={i} className="truncate">• {action}</div>
                      ))}
                      {summary.length > 2 && (
                        <div className="text-gray-500">+{summary.length - 2} more...</div>
                      )}
                    </div>
                  )}
                </div>
              )}

              {/* Expanded content */}
              {isExpanded && (
                <div className="p-3 bg-gray-900 space-y-3">
                  {/* Signal and blocker highlight */}
                  {(signal || blocker) && (
                    <div className={`p-2 rounded border ${
                      signal === 'COMPLETE' ? 'bg-green-900/20 border-green-700/50' :
                      signal === 'BLOCKED' ? 'bg-orange-900/20 border-orange-700/50' :
                      'bg-gray-800 border-gray-700'
                    }`}>
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-xs font-medium text-gray-400">Signal:</span>
                        <SignalBadge signal={signal} />
                        {!signal && <span className="text-xs text-gray-500">None detected</span>}
                      </div>
                      {blocker && (
                        <div className="mt-2">
                          <div className="text-xs font-medium text-orange-400 mb-1">Blocker Reason:</div>
                          <div className="text-xs text-orange-300 bg-orange-900/30 p-2 rounded">
                            {blocker}
                          </div>
                        </div>
                      )}
                    </div>
                  )}

                  {/* Summary */}
                  {summary.length > 0 && (
                    <div>
                      <div className="text-xs font-medium text-cyan-400 mb-1">Actions Summary</div>
                      <div className="text-xs text-gray-300 bg-gray-800 p-2 rounded space-y-1">
                        {summary.map((action, i) => (
                          <div key={i}>• {action}</div>
                        ))}
                      </div>
                    </div>
                  )}

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
                      <div className="text-xs font-medium text-green-400 mb-1">Full Response</div>
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
