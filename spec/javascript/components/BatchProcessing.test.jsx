import React from 'react';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import BatchProcessing from '../../../app/javascript/components/Admin/Intelligence/BatchProcessing';

// ── helpers ──────────────────────────────────────────────────────────────────

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

const META = {
  tasks: [
    {
      key: 'metadata_extraction',
      label: 'Metadata Extraction',
      description: 'Extract metadata.',
      cost_tier: 'low',
      gateway_capability: 'metadata.extract',
    },
  ],
  scopes: [
    { key: 'all_assets', label: 'All Assets', description: 'Every asset.' },
  ],
};

const JOB = {
  id: 1,
  task_type: 'metadata_extraction',
  task_label: 'Metadata Extraction',
  target_scope: 'all_assets',
  status: 'completed',
  concurrency: 25,
  total_count: 10,
  processed_count: 10,
  succeeded_count: 10,
  failed_count: 0,
  progress_percent: 100,
};

// ── tests ─────────────────────────────────────────────────────────────────────

describe('<BatchProcessing />', () => {
  beforeEach(() => {
    jest.spyOn(document, 'querySelector').mockImplementation((sel) =>
      (sel === '[name="csrf-token"]' ? { content: 'csrf' } : null));
  });

  afterEach(() => jest.restoreAllMocks());

  it('renders the header and loads the registry + jobs', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/ai_batch_jobs/task_types': META,
      'GET /api/v1/ai_batch_jobs': { jobs: [JOB] },
    });

    render(<BatchProcessing />);
    expect(screen.getByText('AI Batch Tasks')).toBeInTheDocument();

    await waitFor(() => expect(screen.getAllByText('Metadata Extraction').length).toBeGreaterThan(0));
  });

  it('shows the empty state when there are no jobs', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/ai_batch_jobs/task_types': META,
      'GET /api/v1/ai_batch_jobs': { jobs: [] },
    });

    render(<BatchProcessing />);
    await waitFor(() => expect(screen.getByText(/No batch runs yet/i)).toBeInTheDocument());
  });

  it('launches a batch job through the configuration panel', async () => {
    const created = { ...JOB, id: 2, status: 'queued', progress_percent: 0, processed_count: 0 };
    global.fetch = mockFetch({
      'GET /api/v1/ai_batch_jobs/task_types': META,
      'GET /api/v1/ai_batch_jobs': { jobs: [] },
      'POST /api/v1/ai_batch_jobs': () =>
        Promise.resolve({ ok: true, status: 201, json: () => Promise.resolve(created) }),
    });

    render(<BatchProcessing />);
    await waitFor(() => screen.getByText(/No batch runs yet/i));

    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: /Execute Batch Task/i }));
    });

    await waitFor(() => expect(screen.getByText(/Queued/i)).toBeInTheDocument());
  });

  it('displays an error alert when the registry fetch fails', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/ai_batch_jobs/task_types': () =>
        Promise.resolve({ ok: false, status: 500, json: () => Promise.resolve({ error: 'Server error' }) }),
    });

    render(<BatchProcessing />);
    await waitFor(() => expect(screen.getByText(/Server error/i)).toBeInTheDocument());
  });
});

