import React from 'react';
import { createRoot } from 'react-dom/client';
import Dashboard from './components/Dashboard';
import Login from './components/Login';

import "@hotwired/turbo-rails"

document.addEventListener('DOMContentLoaded', () => {
    const container = document.getElementById('root');

    if (container) {
        const view = container.getAttribute('data-view');
        const root = createRoot(container);

        if (view === 'dashboard') {
            root.render(<Dashboard />);
        } else {
            root.render(<Login />);
        }
    }
});