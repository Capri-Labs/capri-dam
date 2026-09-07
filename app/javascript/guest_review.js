/**
 * Entry point for the unauthenticated guest review page.
 *
 * WHY A SEPARATE BUNDLE FROM `application.js`
 * -------------------------------------------
 * `application.js` mounts the header, sidebar, footer and the whole internal
 * component registry. None of that belongs on a page served to an external
 * party: it would ship the internal UI — including the names of features and
 * routes a guest has no business knowing — to anyone holding a review link,
 * and it would boot navigation into an application they cannot enter.
 *
 * esbuild treats every top-level file in `app/javascript` as an entry point,
 * so this compiles to its own `guest_review.js` with no build config change.
 */
import React from 'react';
import { createRoot } from 'react-dom/client';

import './i18n/index';
import GuestReviewApp from './components/GuestReview/GuestReviewApp';

function boot() {
    const container = document.getElementById('guest-review-root');
    if (!container || container.dataset.mounted === 'true') return;

    // Turbo can fire `turbo:load` more than once for the same document; the
    // flag stops a second React root being created over the first.
    container.dataset.mounted = 'true';

    createRoot(container).render(
        <GuestReviewApp
            config={{
                token: container.dataset.token,
                reviewName: container.dataset.reviewName,
                targetLabel: container.dataset.targetLabel,
            }}
        />,
    );
}

document.addEventListener('turbo:load', boot);
document.addEventListener('DOMContentLoaded', boot);
