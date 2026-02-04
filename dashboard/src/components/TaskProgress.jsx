import React, { useState } from 'react';

function TaskProgress({ prd }) {
  const [hoveredTaskId, setHoveredTaskId] = useState(null);

  if (!prd || !prd.tasks) {
    return (
      <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
        <h3 className="text-sm font-medium text-gray-400 mb-2">Task Progress</h3>
        <p className="text-gray-500">No PRD loaded</p>
      </div>
    );
  }

  const { tasks, progress } = prd;

  // Check if a task is blocked by incomplete dependencies
  const isDependencyBlocked = (task) => {
    if (!task.dependencies?.length) return false;
    return task.dependencies.some(depId => {
      const dep = tasks.find(t => t.id === depId);
      return dep && dep.status !== 'completed';
    });
  };

  // Get incomplete dependencies for a task
  const getIncompleteDependencies = (task) => {
    if (!task.dependencies?.length) return [];
    return task.dependencies.filter(depId => {
      const dep = tasks.find(t => t.id === depId);
      return dep && dep.status !== 'completed';
    });
  };

  // Get effective status considering dependencies
  const getEffectiveStatus = (task) => {
    if (task.status === 'pending' && isDependencyBlocked(task)) {
      return 'dependency_blocked';
    }
    return task.status;
  };

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
    dependency_blocked: (
      <svg className="w-5 h-5 text-yellow-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
      </svg>
    ),
    pending: (
      <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <circle cx="12" cy="12" r="10" strokeWidth={2} />
      </svg>
    )
  };

  // Dependency link icon
  const DependencyIcon = () => (
    <svg className="w-3.5 h-3.5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
    </svg>
  );

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
        {tasks.map((task) => {
          const effectiveStatus = getEffectiveStatus(task);
          const incompleteDeps = getIncompleteDependencies(task);
          const hasDependencies = task.dependencies?.length > 0;
          const isHighlightedAsDep = hoveredTaskId && tasks.find(t => t.id === hoveredTaskId)?.dependencies?.includes(task.id);

          return (
            <div
              key={task.id}
              className={`flex items-center gap-3 p-2 rounded transition-colors ${
                task.status === 'in_progress' ? 'bg-blue-900/20' :
                effectiveStatus === 'dependency_blocked' ? 'bg-yellow-900/10' :
                isHighlightedAsDep ? 'bg-purple-900/20 ring-1 ring-purple-500/50' : ''
              }`}
              onMouseEnter={() => setHoveredTaskId(task.id)}
              onMouseLeave={() => setHoveredTaskId(null)}
            >
              {statusIcons[effectiveStatus] || statusIcons.pending}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-xs text-gray-500 font-mono">#{task.id}</span>
                  {hasDependencies && (
                    <span className="flex items-center gap-0.5" title={`Depends on: ${task.dependencies.map(d => '#' + d).join(', ')}`}>
                      <DependencyIcon />
                    </span>
                  )}
                  <span className={`text-sm truncate ${
                    task.status === 'completed' ? 'text-gray-500 line-through' : 'text-white'
                  }`}>
                    {task.title}
                  </span>
                </div>
                {/* Show blocking dependencies when hovered */}
                {hoveredTaskId === task.id && incompleteDeps.length > 0 && (
                  <div className="text-xs text-yellow-400 mt-1">
                    Blocked by: {incompleteDeps.map(d => '#' + d).join(', ')}
                  </div>
                )}
              </div>
              <span className={`text-xs px-2 py-0.5 rounded ${
                task.status === 'completed' ? 'bg-green-900/50 text-green-400' :
                task.status === 'in_progress' ? 'bg-blue-900/50 text-blue-400' :
                task.status === 'blocked' ? 'bg-orange-900/50 text-orange-400' :
                effectiveStatus === 'dependency_blocked' ? 'bg-yellow-900/50 text-yellow-400' :
                'bg-gray-700 text-gray-400'
              }`}>
                {effectiveStatus === 'dependency_blocked' ? 'waiting' : task.status?.replace('_', ' ')}
              </span>
            </div>
          );
        })}
      </div>

      {/* Summary */}
      {progress && (
        <div className="mt-4 pt-4 border-t border-gray-700 flex flex-wrap gap-x-4 gap-y-1 text-xs">
          <span className="text-green-400">{progress.completed} completed</span>
          <span className="text-blue-400">{progress.inProgress} in progress</span>
          <span className="text-orange-400">{progress.blocked} blocked</span>
          {progress.dependencyBlocked > 0 && (
            <span className="text-yellow-400">{progress.dependencyBlocked} waiting</span>
          )}
          {progress.available > 0 && (
            <span className="text-purple-400">{progress.available} available</span>
          )}
          <span className="text-gray-400">{progress.pending} pending</span>
        </div>
      )}
    </div>
  );
}

export default TaskProgress;
