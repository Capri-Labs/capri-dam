import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import ProvenanceC2PA from '../../../app/javascript/components/Admin/Intelligence/ProvenanceC2PA';

// ── helpers ───────────────────────────────────────────────────────────────────

function mockFetch(routes) {
  return jest.fn((url, opts = {}) => {
    const method = opts.method || 'GET';
    const key = Object.keys(routes)
      .filter((k) => {
        const [m, path] = k.split(' ');
        return m === method && url.startsWith(path);
      })
      .sort((a, b) => b.split(' ')[1].length - a.split(' ')[1].length)[0];
    const handler = key ? routes[key] : null;
    if (!handler) return Promise.resolve({ ok: false, status: 404, json: () => Promise.resolve({}) });
    if (typeof handler === 'function') return handler(opts);
    return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(handler) });
  });
}

// ── fixtures ──────────────────────────────────────────────────────────────────

const STATS = {
  total_assets: 120, verified: 80, ai_flagged: 5,
  missing: 20, invalid: 3, signed: 12, unchecked: 7, ai_modified: 4,
};

const RECORDS_RESP = {
  total: 2, page: 1, per_page: 50,
  records: [
    { id: 1, asset_uuid: 'uuid-1', asset_title: 'Banner.jpg', manifest_status: 'verified', is_ai_modified: false, claim_generator: 'Adobe Photoshop 25.0', verified_at: '2026-06-28T10:00:00Z' },
    { id: 2, asset_uuid: 'uuid-2', asset_title: 'HeroVideo.mp4', manifest_status: 'ai_modified', is_ai_modified: true, claim_generator: null, verified_at: null },
  ],
};

const CONFIG = {
  id: 1, gateway_c2pa_enabled: false, auto_verify_on_ingest: false,
  auto_sign_on_ingest: false, require_c2pa_on_import: false,
  ai_disclosure_required: true, signing_issuer_name: 'Capri DAM',
  signing_org: 'Acme Corp', trust_store_urls: [], verification_strictness: 'lenient',
  policy_notes: null,
};

const TASK_META = {
  tasks: [
    { key: 'c2pa_verify', label: 'C2PA Verification', description: 'Verify manifests.', cost_tier: 'low', gateway_capability: 'c2pa.verify' },
  ],
  scopes: [
    { key: 'unverified_assets', label: 'Assets Without C2PA Verification', description: 'Unverified.' },
  ],
};

const BASE_ROUTES = {
  'GET /api/v1/asset_provenance_records/stats': STATS,
  'GET /api/v1/asset_provenance_records': RECORDS_RESP,
  'GET /api/v1/c2pa_configuration': CONFIG,
  'GET /api/v1/ai_batch_jobs/task_types': TASK_META,
};

// ── i18n stub ─────────────────────────────────────────────────────────────────

const T = {
  'provenance.title':        'Provenance & C2PA',
  'provenance.subtitle':     'Track content credentials.',
  'provenance.tabs.records': 'Provenance Records',
  'provenance.tabs.policy':  'Policy Settings',
  'provenance.tabs.batch':   'Batch Actions',
  'provenance.stats.verified':   'Verified',
  'provenance.stats.aiModified': 'AI-Modified',
  'provenance.stats.missing':    'No Manifest',
  'provenance.stats.invalid':    'Invalid Manifest',
  'provenance.stats.signed':     'DAM-Signed',
  'provenance.policy.gatewaySection': 'Gateway Integration',
  'provenance.policy.ingestSection':  'Ingest Hooks',
  'provenance.policy.signingSection': 'Signing Identity',
  'provenance.policy.signingIssuerName': 'Signing Issuer Name',
  'provenance.policy.signingOrg':        'Signing Organisation',
  'provenance.policy.strictness':        'Verification Strictness',
  'provenance.policy.policyNotes':       'Policy Notes',
  'provenance.policy.save':    'Save Policy',
  'provenance.policy.saving':  'Saving...',
  'provenance.policy.saved':   'Policy saved successfully.',
  'provenance.batch.task':        'C2PA Task',
  'provenance.batch.scope':       'Target Dataset',
  'provenance.batch.concurrency': 'Concurrency',
  'provenance.batch.launch':      'Launch Batch Task',
  'provenance.batch.launching':   'Launching...',
  'provenance.table.filterStatus': 'Filter by status',
  'provenance.table.asset':    'Asset',
  'provenance.table.status':   'Manifest Status',
  'provenance.empty':          'No provenance records yet.',
  'common.refresh':            'Refresh',
  'common.all':                'All',
};

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key, opts) => T[key] || opts?.defaultValue || key,
  }),
}));

// MUI uses ResizeObserver internally; polyfill for jsdom
global.ResizeObserver = class ResizeObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
};

// ── lifecycle ─────────────────────────────────────────────────────────────────

beforeEach(() => {
  // Set CSRF meta WITHOUT wiping document.head. Overwriting document.head.innerHTML
  // removes Emotion's cached <style> reference nodes, causing insertBefore to throw
  // NotFoundError when Emotion tries to insert new CSS in subsequent tests.
  let csrfMeta = document.head.querySelector('[name="csrf-token"]');
  if (!csrfMeta) {
    csrfMeta = document.createElement('meta');
    csrfMeta.setAttribute('name', 'csrf-token');
    document.head.appendChild(csrfMeta);
  }
  csrfMeta.setAttribute('content', 'test-csrf');
  global.fetch = mockFetch(BASE_ROUTES);
});

afterEach(() => jest.restoreAllMocks());

// ── tests ─────────────────────────────────────────────────────────────────────

describe('<ProvenanceC2PA />', () => {
  it('renders the header and loads stats and records', async () => {
    render(<ProvenanceC2PA />);
    await waitFor(() => expect(screen.getByText('Banner.jpg')).toBeInTheDocument());
    expect(screen.getByText('Provenance & C2PA')).toBeInTheDocument();
    expect(screen.getByText('80')).toBeInTheDocument();
  });

  it('shows the AI-modified chip for ai_modified records', async () => {
    render(<ProvenanceC2PA />);
    await waitFor(() => expect(screen.getByText('Banner.jpg')).toBeInTheDocument());
    expect(screen.getAllByText('AI').length).toBeGreaterThan(0);
  });

  it('switches to the Policy Settings tab and renders form fields', async () => {
    render(<ProvenanceC2PA />);
    await waitFor(() => screen.getByText('Banner.jpg'));
    fireEvent.click(screen.getByText(/policy settings/i));
    await waitFor(() => expect(screen.getByLabelText(/Signing Issuer Name/i)).toBeInTheDocument());
  });

  it('saves the policy config via PATCH', async () => {
    let patchCalled = false;
    global.fetch = mockFetch({
      ...BASE_ROUTES,
      'PATCH /api/v1/c2pa_configuration': (opts) => {
        patchCalled = true;
        const body = JSON.parse(opts.body);
        expect(body.c2pa_configuration).toBeDefined();
        return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({ message: 'ok', config: CONFIG }) });
      },
    });
    render(<ProvenanceC2PA />);
    await waitFor(() => screen.getByText('Banner.jpg'));
    fireEvent.click(screen.getByText(/policy settings/i));
    await waitFor(() => screen.getByText(/save policy/i));
    fireEvent.click(screen.getByText(/save policy/i));
    await waitFor(() => expect(patchCalled).toBe(true));
  });

  it('switches to the Batch Actions tab and shows C2PA task options', async () => {
    render(<ProvenanceC2PA />);
    await waitFor(() => screen.getByText('Banner.jpg'));
    fireEvent.click(screen.getByText(/batch actions/i));
    await waitFor(() => expect(screen.getByText('C2PA Verification')).toBeInTheDocument());
  });

  it('shows an error alert when the stats API fails', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/asset_provenance_records/stats': () =>
        Promise.resolve({ ok: false, status: 500, json: () => Promise.resolve({ error: 'Internal error' }) }),
      'GET /api/v1/asset_provenance_records': RECORDS_RESP,
      'GET /api/v1/c2pa_configuration': CONFIG,
    });
    render(<ProvenanceC2PA />);
    await waitFor(() => expect(screen.getByRole('alert')).toBeInTheDocument());
  });
});
