import React from 'react';
import { createRoot } from 'react-dom/client';
import Dashboard from './components/Dashboard';
import Login from './components/Login';
import Settings from './components/Settings';

import "@hotwired/turbo-rails"
import SystemAccountShow from "./components/system_accounts/SystemAccountShow";
import SystemAccountNew from "./components/system_accounts/SystemAccountNew";

// Use 'turbo:load' instead of 'DOMContentLoaded'
document.addEventListener('turbo:load', () => {
    const container = document.getElementById('root');
    if (!container) return;

    container.innerHTML = '';
    const root = createRoot(container);
    const view = container.getAttribute('data-view');
    const props = Object.assign({}, container.dataset);

    if (view === 'dashboard') {
        root.render(<Dashboard {...props} />);
    } else if (view === 'settings') {
        root.render(<Settings {...props} />);
    } else if (view === 'system_account_show') {
        root.render(<SystemAccountShow {...props} />);
    } else if (view === 'system_account_new') {
        root.render(<SystemAccountNew {...props} />);
    } else {
        root.render(<Login />);
    }
});