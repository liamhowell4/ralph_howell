import React from 'react';
import { usePolling } from '../hooks/usePolling';
import { fetchProjects } from '../api';
import ProjectCard from '../components/ProjectCard';

function OverviewPage() {
  const { data: projects, error, loading } = usePolling(fetchProjects, 5000);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="animate-spin w-8 h-8 border-2 border-purple-500 border-t-transparent rounded-full" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-900/30 border border-red-700 rounded-lg p-6 text-center">
        <h2 className="text-lg font-semibold text-red-400 mb-2">Connection Error</h2>
        <p className="text-gray-400">{error}</p>
        <p className="text-sm text-gray-500 mt-2">
          Make sure the monitor server is running on port 3500
        </p>
      </div>
    );
  }

  if (!projects || projects.length === 0) {
    return (
      <div className="text-center py-20">
        <div className="w-20 h-20 bg-gray-800 rounded-full flex items-center justify-center mx-auto mb-4">
          <svg className="w-10 h-10 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
          </svg>
        </div>
        <h2 className="text-xl font-semibold text-gray-300 mb-2">No Projects Running</h2>
        <p className="text-gray-500 max-w-md mx-auto">
          Start a Ralph loop in your project directory to see it here.
        </p>
        <div className="mt-6 p-4 bg-gray-800 rounded-lg inline-block text-left">
          <code className="text-sm text-purple-400">.\ralph.ps1 -FromMd -PrdPath ".\PROMPT.md"</code>
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-lg font-semibold text-gray-200">
          Active Projects ({projects.length})
        </h2>
        <div className="text-sm text-gray-500">
          Auto-refreshes every 5 seconds
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {projects.map((project) => (
          <ProjectCard key={project.port} project={project} />
        ))}
      </div>
    </div>
  );
}

export default OverviewPage;
