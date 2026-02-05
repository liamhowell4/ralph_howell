import React from 'react';
import { Link } from 'react-router-dom';

function ProjectCard({ project }) {
  const { name, port, path, isAlive, state, engine, model } = project;

  const status = state?.status || (isAlive ? 'unknown' : 'offline');
  const iteration = state?.currentIteration || 0;

  // Clean up model name for display
  // Only show model name for claude engine; other engines don't use the model field
  const shortModel = engine && engine !== 'claude'
    ? engine
    : model
      ? model.replace(/^claude-/, '').replace(/-\d{8}$/, '')
      : null;

  const statusColors = {
    running: 'bg-green-500',
    paused: 'bg-yellow-500',
    completed: 'bg-blue-500',
    circuit_breaker: 'bg-orange-500',
    max_iterations: 'bg-purple-500',
    offline: 'bg-gray-500',
    unknown: 'bg-gray-500',
    initialized: 'bg-gray-400',
    error: 'bg-red-500'
  };

  const statusLabels = {
    running: 'Running',
    paused: 'Paused',
    completed: 'Completed',
    circuit_breaker: 'Circuit Breaker',
    max_iterations: 'Max Iterations',
    offline: 'Offline',
    unknown: 'Unknown',
    initialized: 'Ready',
    error: 'Error'
  };

  return (
    <Link
      to={`/project/${port}`}
      className="block bg-gray-800 border border-gray-700 rounded-lg p-4 hover:border-purple-500 transition-colors"
    >
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2">
          <div className={`w-3 h-3 rounded-full ${statusColors[status]} ${status === 'running' ? 'animate-pulse' : ''}`} />
          <span className="text-sm text-gray-400">{statusLabels[status]}</span>
        </div>
        <span className="text-xs text-gray-500">:{port}</span>
      </div>

      <h3 className="text-lg font-semibold text-white mb-1 truncate">{name}</h3>
      <p className="text-sm text-gray-500 truncate mb-3" title={path}>{path}</p>

      {shortModel && (
        <div className="mb-3">
          <span className="text-xs bg-gray-700 text-gray-300 px-2 py-0.5 rounded-full" title={`${engine || 'unknown'} / ${model}`}>
            {shortModel}
          </span>
        </div>
      )}

      {isAlive && state && (
        <div className="flex items-center justify-between text-sm">
          <span className="text-gray-400">Iteration</span>
          <span className="text-white font-mono">{iteration}</span>
        </div>
      )}

      {!isAlive && (
        <div className="text-sm text-gray-500 italic">
          Project API not responding
        </div>
      )}
    </Link>
  );
}

export default ProjectCard;
