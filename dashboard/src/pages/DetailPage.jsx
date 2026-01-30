import React, { useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useProjectState } from '../hooks/useProjectState';
import { stopProject } from '../api';
import StatusPanel from '../components/StatusPanel';
import TaskProgress from '../components/TaskProgress';
import UsageMeter from '../components/UsageMeter';
import CircuitBreaker from '../components/CircuitBreaker';
import LogViewer from '../components/LogViewer';
import FileChanges from '../components/FileChanges';
import ConfigEditor from '../components/ConfigEditor';
import ConversationLog from '../components/ConversationLog';

function DetailPage() {
  const { port } = useParams();
  const portNum = parseInt(port);

  const {
    state,
    prd,
    config,
    logs,
    rateLimit,
    changes,
    conversations,
    loading,
    error,
    refresh
  } = useProjectState(portNum, 2000);

  const [showConfig, setShowConfig] = useState(false);
  const [stopping, setStopping] = useState(false);

  const handleStop = async () => {
    if (stopping) return;
    setStopping(true);
    try {
      await stopProject(portNum);
      refresh();
    } catch (e) {
      console.error('Failed to stop:', e);
    } finally {
      setStopping(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="animate-spin w-8 h-8 border-2 border-purple-500 border-t-transparent rounded-full" />
      </div>
    );
  }

  if (error) {
    return (
      <div>
        <Link to="/" className="text-purple-400 hover:text-purple-300 mb-4 inline-flex items-center gap-1">
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          Back to Overview
        </Link>
        <div className="bg-red-900/30 border border-red-700 rounded-lg p-6 text-center mt-4">
          <h2 className="text-lg font-semibold text-red-400 mb-2">Project Unavailable</h2>
          <p className="text-gray-400">{error}</p>
        </div>
      </div>
    );
  }

  const projectName = prd?.projectName || `Project on port ${portNum}`;

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <Link to="/" className="text-purple-400 hover:text-purple-300 mb-2 inline-flex items-center gap-1 text-sm">
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
            Back to Overview
          </Link>
          <h1 className="text-2xl font-bold text-white">{projectName}</h1>
          <p className="text-gray-400 text-sm">Port {portNum}</p>
        </div>

        <div className="flex gap-2">
          <button
            onClick={() => setShowConfig(!showConfig)}
            className="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg text-sm font-medium transition-colors"
          >
            {showConfig ? 'Hide Config' : 'Edit Config'}
          </button>

          {state?.status === 'running' && (
            <button
              onClick={handleStop}
              disabled={stopping}
              className="px-4 py-2 bg-red-600 hover:bg-red-500 disabled:bg-red-800 rounded-lg text-sm font-medium transition-colors"
            >
              {stopping ? 'Stopping...' : 'Stop Loop'}
            </button>
          )}
        </div>
      </div>

      {/* Config Editor */}
      {showConfig && (
        <div className="mb-6">
          <ConfigEditor port={portNum} config={config} onSave={refresh} />
        </div>
      )}

      {/* Status Row */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <StatusPanel state={state} config={config} />
        <UsageMeter rateLimit={rateLimit} />
        <CircuitBreaker state={state} config={config} />
      </div>

      {/* Task Progress */}
      <div className="mb-6">
        <TaskProgress prd={prd} />
      </div>

      {/* Conversation Log */}
      <div className="mb-6">
        <ConversationLog conversations={conversations} />
      </div>

      {/* Bottom Row */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <LogViewer logs={logs} />
        <FileChanges changes={changes} />
      </div>
    </div>
  );
}

export default DetailPage;
