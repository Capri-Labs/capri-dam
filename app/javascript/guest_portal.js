/**
 * Entry point for the unauthenticated distribution portal.
 *
 * WHY A SEPARATE BUNDLE FROM `application.js`
 * -------------------------------------------
 * `application.js` mounts the header, sidebar, footer and the whole internal
 * component registry. None of that belongs on a page served to an external
 * party: it would ship the internal UI — including the names of features and
 * routes a partner has no business knowing — to anyone holding a portal link,
 * and it would boot navigation into an application they cannot enter.
 *
 * It is also separate from `guest_review.js`. The two surfaces share a
 * credential but not a job: a reviewer annotates images, a partner collects
 * files. Bundling them together would ship the annotation editor to every
 * partner who only ever needed a download button.
 *
 * esbuild treats every top-level file in `app/javascript` as an entry point,
 * so this compiles to its own `guest_portal.js` with no build config change.
 */
import React from 'react';
import { createRoot } from 'react-dom/client';

import './i18n/index';
import GuestPortalApp from './components/GuestPortal/GuestPortalApp';

function boot() {
    const container = document.getElementById('guest-portal-root');
    if (!container || container.dataset.mounted === 'true') return;

    // Turbo can fire `turbo:load` more than once for the same document; the
    // flag stops a second React root being created over the first.
    container.dataset.mounted = 'true';

    createRoot(container).render(
        <GuestPortalApp
            config={{
                token: container.dataset.token,
                portalName: container.dataset.portalName,
                headline: container.dataset.headline,
                message: container.dataset.message,
                accent: container.dataset.accent,
                requireEmail: container.dataset.requireEmail === 'true',
                identified: container.dataset.identified === 'true',
                guestName: container.dataset.guestName,
            }}
        />,
    );
}

document.addEventListener('turbo:load', boot);
document.addEventListener('DOMContentLoaded', boot);
