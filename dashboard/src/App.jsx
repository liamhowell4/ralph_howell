import React from 'react';
import { Routes, Route, Link } from 'react-router-dom';
import OverviewPage from './pages/OverviewPage';
import DetailPage from './pages/DetailPage';

function App() {
  return (
    <div className="min-h-screen bg-gray-900">
      {/* Header */}
      <header className="bg-gray-800 border-b border-gray-700">
        <div className="max-w-7xl mx-auto px-4 py-4">
          <Link to="/" className="flex items-center gap-3">
            <div className="w-10 h-10 bg-gradient-to-br from-purple-500 to-pink-500 rounded-lg flex items-center justify-center">
              <span className="text-white font-bold text-xl">R</span>
            </div>
            <div>
              <h1 className="text-xl font-bold text-white">Ralph Howell Loop</h1>
              <p className="text-sm text-gray-400">Autonomous Development Loop Monitor</p>
            </div>
          </Link>
        </div>
      </header>

      {/* Main content */}
      <main className="max-w-7xl mx-auto px-4 py-6">
        <Routes>
          <Route path="/" element={<OverviewPage />} />
          <Route path="/project/:port" element={<DetailPage />} />
        </Routes>
      </main>
    </div>
  );
}

export default App;
