import React, { useState, useEffect } from 'react';
import { updateProjectConfig } from '../api';

function ConfigEditor({ port, config, onSave }) {
  const [editedConfig, setEditedConfig] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(false);

  useEffect(() => {
    if (config) {
      setEditedConfig(JSON.stringify(config, null, 2));
    }
  }, [config]);

  const handleSave = async () => {
    setSaving(true);
    setError(null);
    setSuccess(false);

    try {
      const parsed = JSON.parse(editedConfig);
      await updateProjectConfig(port, parsed);
      setSuccess(true);
      if (onSave) onSave();

      // Clear success message after 3 seconds
      setTimeout(() => setSuccess(false), 3000);
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  };

  const handleReset = () => {
    if (config) {
      setEditedConfig(JSON.stringify(config, null, 2));
      setError(null);
    }
  };

  if (!config) {
    return (
      <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
        <h3 className="text-sm font-medium text-gray-400">Configuration</h3>
        <p className="text-gray-500 mt-2">No configuration available</p>
      </div>
    );
  }

  return (
    <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-medium text-gray-400">Configuration</h3>
        <div className="flex gap-2">
          <button
            onClick={handleReset}
            className="px-3 py-1 text-sm bg-gray-700 hover:bg-gray-600 rounded transition-colors"
          >
            Reset
          </button>
          <button
            onClick={handleSave}
            disabled={saving}
            className="px-3 py-1 text-sm bg-purple-600 hover:bg-purple-500 disabled:bg-purple-800 rounded transition-colors"
          >
            {saving ? 'Saving...' : 'Save'}
          </button>
        </div>
      </div>

      {error && (
        <div className="mb-3 p-2 bg-red-900/30 border border-red-800 rounded text-sm text-red-400">
          {error}
        </div>
      )}

      {success && (
        <div className="mb-3 p-2 bg-green-900/30 border border-green-800 rounded text-sm text-green-400">
          Configuration saved! Changes will apply on next iteration.
        </div>
      )}

      <textarea
        value={editedConfig || ''}
        onChange={(e) => setEditedConfig(e.target.value)}
        className="w-full h-64 bg-gray-900 border border-gray-700 rounded p-3 font-mono text-sm text-gray-300 focus:outline-none focus:border-purple-500"
        spellCheck={false}
      />

      <div className="mt-2 text-xs text-gray-500">
        Edit configuration JSON directly. Changes take effect on the next iteration.
      </div>
    </div>
  );
}

export default ConfigEditor;
