import React from 'react';
import { createRoot } from 'react-dom/client';
import "@hotwired/turbo-rails"

// ── i18n — must be imported before any component that calls useTranslation ──
import './i18n/index';

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
    // --- 0. DEFENSIVE CLEANUP: orphaned MUI modal/backdrop portals ---
    // MUI Dialogs/Modals render their Backdrop via a React Portal appended
    // directly to `document.body` (outside the `#root` container Turbo
    // manages below). If the user navigates away (via Turbo.visit /
    // navigateTo) while a Dialog is still open, the old React root is
    // abandoned via `innerHTML = ''` rather than `root.unmount()`, so no
    // React unmount/cleanup effect ever runs — the Backdrop portal node (and
    // any `document.body` scroll-lock styles MUI applied) are left behind,
    // covering the whole viewport and silently blocking every click on
    // whatever page loads next. This happened concretely with the Duplicate
    // Manager's "Go to Folder"/"Go to asset" links (only closing the modal
    // *before* navigating avoids creating a new orphan — see
    // DuplicateResolutionModal.jsx), but as a safety net for any other modal
    // that might get left open across a Turbo navigation, sweep and remove
    // any stray top-level MUI portal nodes and reset the body lock styles on
    // every page load (including Turbo's cached "Back" restores).
    document.querySelectorAll('body > .MuiModal-root, body > .MuiBackdrop-root, body > .MuiPopover-root')
        .forEach((node) => node.remove());
    document.body.style.removeProperty('overflow');
    document.body.style.removeProperty('padding-right');
    document.body.removeAttribute('aria-hidden');

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