import React from 'react';
import { createRoot } from 'react-dom/client';
import "@hotwired/turbo-rails"

// Components
import Header from './components/Header'; // Import your Header
import Dashboard from './components/Dashboard';
import Settings from './components/Settings';
import SystemAccountShow from "./components/system_accounts/SystemAccountShow";
import SystemAccountNew from "./components/system_accounts/SystemAccountNew";
import Login from './components/Login';
import { NotificationProvider } from './context/NotificationContext';
import UserGroupsManager from './components/Admin/UserGroupsManager';
import UsersManager from './components/Admin/UsersManager';
import EmailEngineManager from './components/Admin/EmailEngineManager';
import App from './components/App';
import AssetExplorer from "./components/AssetExplorer";
import WorkflowDashboard from "./components/WorkflowDashboard";
import WorkflowContainer from "./components/WorkflowContainer";

document.addEventListener('turbo:load', () => {
    // --- 1. MOUNT THE HEADER ---
    const headerContainer = document.getElementById('header-root');
    if (headerContainer) {
        headerContainer.innerHTML = ''; // Clear to prevent duplicates
        const headerRoot = createRoot(headerContainer);
        const headerProps = {
            userName: headerContainer.dataset.userName,
            isSignedIn: headerContainer.dataset.signedIn === 'true'
        };
        headerRoot.render(<Header {...headerProps} />);
    }

    // --- 2. MOUNT THE MAIN CONTENT ---
    const mainContainer = document.getElementById('root');
    if (mainContainer) {
        mainContainer.innerHTML = ''; // Clear for Turbo refreshes
        const mainRoot = createRoot(mainContainer);
        const view = mainContainer.getAttribute('data-view');
        const props = Object.assign({}, mainContainer.dataset);

        // Wrap the components inside the Provider layout block
        const renderWithContext = (Component) => (
            <NotificationProvider>
                {Component}
            </NotificationProvider>
        );

        if (view === 'dashboard') {
            mainRoot.render(renderWithContext(<Dashboard {...props} />));
        } else if (view === 'settings') {
            mainRoot.render(renderWithContext(<Settings {...props} />));
        } else if (view === 'system_account_show') {
            mainRoot.render(renderWithContext(<SystemAccountShow {...props} />));
        } else if (view === 'system_account_new') {
            mainRoot.render(renderWithContext(<SystemAccountNew {...props} />));
        } else if (view === 'user_groups') {
            mainRoot.render(renderWithContext(<UserGroupsManager {...props} />));
        } else if (view === 'users') {
            mainRoot.render(renderWithContext(<UsersManager {...props} />));
        } else if (view === 'email_engine') {
            mainRoot.render(renderWithContext(<EmailEngineManager {...props} />));
        } else if (view === 'app') {
            mainRoot.render(renderWithContext(<App {...props} />));
        } else if (view === 'asset_explorer') {
            mainRoot.render(renderWithContext(<AssetExplorer {...props} />));
        }  else if (view === 'workflows_container') {
            mainRoot.render(renderWithContext(<WorkflowContainer {...props} />));

        } else if (view === 'workflow_dashboard') {
            mainRoot.render(renderWithContext(<WorkflowDashboard {...props} />));

        } else {
            mainRoot.render(renderWithContext(<Login />));
        }
    }
});