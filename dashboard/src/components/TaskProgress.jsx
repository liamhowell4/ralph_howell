import React from 'react';

function TaskProgress({ prd }) {
  if (!prd || !prd.tasks) {
    return (
      <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
        <h3 className="text-sm font-medium text-gray-400 mb-2">Task Progress</h3>
        <p className="text-gray-500">No PRD loaded</p>
      </div>
    );
  }

  const { tasks, progress } = prd;

  const statusIcons = {
    completed: (
      <svg className="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
      </svg>
    ),
    in_progress: (
      <svg className="w-5 h-5 text-blue-400 animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
      </svg>
    ),
    blocked: (
      <svg className="w-5 h-5 text-orange-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
      </svg>
    ),
    pending: (
      <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <circle cx="12" cy="12" r="10" strokeWidth={2} />
      </svg>
    )
  };

  return (
    <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-medium text-gray-400">Task Progress</h3>
        {progress && (
          <span className="text-sm text-gray-500">
            {progress.completed}/{progress.total} ({progress.percentComplete}%)
          </span>
        )}
      </div>

      {/* Progress bar */}
      {progress && (
        <div className="h-2 bg-gray-700 rounded-full mb-4 overflow-hidden">
          <div
            className="h-full bg-gradient-to-r from-purple-500 to-pink-500 transition-all duration-500"
            style={{ width: `${progress.percentComplete}%` }}
          />
        </div>
      )}

      {/* Task list */}
      <div className="space-y-2 max-h-64 overflow-y-auto">
        {tasks.map((task) => (
          <div
            key={task.id}
            className={`flex items-center gap-3 p-2 rounded ${
              task.status === 'in_progress' ? 'bg-blue-900/20' : ''
            }`}
          >
            {statusIcons[task.status] || statusIcons.pending}
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-500 font-mono">#{task.id}</span>
                <span className={`text-sm truncate ${
                  task.status === 'completed' ? 'text-gray-500 line-through' : 'text-white'
                }`}>
                  {task.title}
                </span>
              </div>
            </div>
            <span className={`text-xs px-2 py-0.5 rounded ${
              task.status === 'completed' ? 'bg-green-900/50 text-green-400' :
              task.status === 'in_progress' ? 'bg-blue-900/50 text-blue-400' :
              task.status === 'blocked' ? 'bg-orange-900/50 text-orange-400' :
              'bg-gray-700 text-gray-400'
            }`}>
              {task.status?.replace('_', ' ')}
            </span>
          </div>
        ))}
      </div>

      {/* Summary */}
      {progress && (
        <div className="mt-4 pt-4 border-t border-gray-700 flex gap-4 text-xs">
          <span className="text-green-400">{progress.completed} completed</span>
          <span className="text-blue-400">{progress.inProgress} in progress</span>
          <span className="text-orange-400">{progress.blocked} blocked</span>
          <span className="text-gray-400">{progress.pending} pending</span>
        </div>
      )}
    </div>
  );
}

export default TaskProgress;
