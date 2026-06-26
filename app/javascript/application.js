import React from 'react';
import { createRoot } from 'react-dom/client';
import "@hotwired/turbo-rails"

// Components
import Header from './components/Layout/Header';
import Login from './components/Login/Login';
import { NotificationProvider } from './context/NotificationContext';
import Sidebar from './components/Sidebar';
import Footer from './components/Layout/Footer';
import {COMPONENT_REGISTRY} from "./components/Registry";

// Helper to wrap components
const withContext = (Component, props) => (
    <NotificationProvider>
        <Component {...props} />
    </NotificationProvider>
);

document.addEventListener('turbo:load', () => {
    // --- 1. MOUNT THE HEADER ---
    const headerContainer = document.getElementById('header-root');
    if (headerContainer) {
        headerContainer.innerHTML = ''; // Clear to prevent duplicates
        const headerRoot = createRoot(headerContainer);
        const headerProps = {
            userName:         headerContainer.dataset.userName,
            isSignedIn:       headerContainer.dataset.signedIn === 'true',
            isAdmin:          headerContainer.dataset.isAdmin === 'true',
            isSuperAdmin:     headerContainer.dataset.isSuperAdmin === 'true',
            impersonating:    headerContainer.dataset.impersonating === 'true',
            impersonatedUser: headerContainer.dataset.impersonatedUser || null,
            trueUserName:     headerContainer.dataset.trueUserName || null,
        };
        headerRoot.render(<Header {...headerProps} />);
    }

    const sidebarRootElement = document.getElementById('react-sidebar-root');
    if (sidebarRootElement) {
        // Read the active view defined by the Rails Controller
        const activeView = sidebarRootElement.getAttribute('data-active-view');
        const sidebarRoot = createRoot(sidebarRootElement);
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

    // --- MOUNT THE MAIN CONTENT ---
    const mainContainer = document.getElementById('root');
    if (mainContainer) {
        mainContainer.innerHTML = ''; // Clear for Turbo refreshes
        const mainRoot = createRoot(mainContainer);
        const viewKey = mainContainer.getAttribute('data-view');
        const props = Object.assign({}, mainContainer.dataset);

        const ComponentToRender = COMPONENT_REGISTRY[viewKey];

        if (ComponentToRender) {
            mainRoot.render(withContext(ComponentToRender, props));
        } else {
            // Default fallback
            mainRoot.render(withContext(Login, props));
        }
    }
});