import React from 'react';
import { createRoot } from 'react-dom/client';
import "@hotwired/turbo-rails"

// Components
import Header from './components/Layout/Header'; // Import your Header
import Settings from './components/Settings';
import SystemAccountShow from "./components/system_accounts/SystemAccountShow";
import SystemAccountNew from "./components/system_accounts/SystemAccountNew";
import Login from './components/Login/Login';
import { NotificationProvider } from './context/NotificationContext';
import UserGroupsManager from './components/Admin/UserGroupsManager';
import UsersManager from './components/Admin/UsersManager';
import EmailEngineManager from './components/Admin/EmailEngineManager';
import App from './components/App';
import AssetExplorer from "./components/Folders/AssetExplorer";
import WorkflowDashboard from "./components/WorkflowDashboard";
import WorkflowContainer from "./components/WorkflowContainer";
import ReportsManager from "./components/Admin/ReportsManager";
import DashboardManager from "./components/Dashboard/DashboardManager";
import FoldersManager from "./components/Folders/FoldersManager";
import BinManager from "./components/Bin/BinManager";
import DuplicateManager from "./components/Duplicates/DuplicateManager";
import Sidebar from './components/Sidebar';
import Footer from './components/Layout/Footer';
import SearchScreen from "./components/Search/SearchScreen";
import CollectionsWorkspace from './components/Collections/index';

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

    const sidebarRootElement = document.getElementById('react-sidebar-root');
    if (sidebarRootElement) {
        // Read the active view defined by the Rails Controller
        const activeView = sidebarRootElement.getAttribute('data-active-view');

        const sidebarRoot = createRoot(sidebarRootElement);

        console.log(activeView)

        sidebarRoot.render(
            <Sidebar
                activeView={activeView}
                onNavigate={(viewId) => {
                    // Handle global navigation if needed
                    window.location.href = getUrlForView(viewId);
                }}
            />
        );
    }

    const footerContainer = document.getElementById('react-footer-root');
    if (footerContainer && !footerContainer.hasChildNodes()) {
        const footerRoot = createRoot(footerContainer);
        footerRoot.render(<Footer />);
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
            mainRoot.render(renderWithContext(<DashboardManager {...props} />));
        } else if (view === 'folders') {
            mainRoot.render(renderWithContext(<FoldersManager {...props} />));
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

        } else if (view === 'reports') {
            mainRoot.render(renderWithContext(<ReportsManager {...props} />));

        } else if (view === 'bin') {
            mainRoot.render(renderWithContext(<BinManager {...props} />));
        } else if (view === 'duplicates') {
            mainRoot.render(renderWithContext(<DuplicateManager {...props} />));

        } else if (view === 'SearchScreen') {
            mainRoot.render(renderWithContext(<SearchScreen {...props} />));

        }  else if (view === 'collectionsView') {
            mainRoot.render(renderWithContext(<CollectionsWorkspace {...props} />));

        } else {
            mainRoot.render(renderWithContext(<Login />));
        }
    }
});