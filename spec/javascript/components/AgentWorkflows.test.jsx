import React from 'react';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import AgentWorkflows from '../../../app/javascript/components/Admin/Intelligence/AgentWorkflows';

// ── helpers ──────────────────────────────────────────────────────────────────

function mockFetch(routes) {
  return jest.fn((url, opts = {}) => {
    const method = opts.method || 'GET';
    // Choose the LONGEST matching path so that
    // "GET /api/v1/agent_workflows/1/executions" wins over
    // "GET /api/v1/agent_workflows" for the executions URL.
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

const WORKFLOW = {
  id: 1,
  name: 'Auto-SEO Enrichment',
  description: 'Maps semantic keywords on ingestion.',
  trigger_event: 'asset.staged',
  agent_model: 'gpt-4o-mini',
  tools_enabled: ['VisualContextExtractor', 'SEOTaxonomyMapper'],
  active: true,
  metadata: {},
  reliability: 99.2,
  avg_duration_ms: 1400,
  execution_count: 12,
};

const EXECUTIONS = {
  total: 1,
  page: 1,
  per_page: 20,
  executions: [
    {
      id: 10,
      agent_workflow_id: 1,
      status: 'success',
      summary: 'Mapped 4 tags to summer_hero.jpg',
      started_at: new Date().toISOString(),
      duration_ms: 1400,
    },
  ],
};

// ── tests ─────────────────────────────────────────────────────────────────────

describe('<AgentWorkflows />', () => {
  beforeEach(() => {
    jest.spyOn(document, 'querySelector').mockImplementation((sel) =>
      (sel === '[name="csrf-token"]' ? { content: 'csrf' } : null));
  });

  afterEach(() => jest.restoreAllMocks());

  it('renders the header and loads workflows from the API', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/agent_workflows': [WORKFLOW],
      'GET /api/v1/agent_workflows/1/executions': EXECUTIONS,
    });

    render(<AgentWorkflows />);
    expect(screen.getByText('Agent Automations')).toBeInTheDocument();

    await waitFor(() => expect(screen.getByText('Auto-SEO Enrichment')).toBeInTheDocument());
    expect(screen.getByText('99.2%')).toBeInTheDocument();
  });

  it('shows the empty state when there are no workflows', async () => {
    global.fetch = mockFetch({ 'GET /api/v1/agent_workflows': [] });
    render(<AgentWorkflows />);
    await waitFor(() => expect(screen.getByText(/No workflows yet/i)).toBeInTheDocument());
  });

  it('opens the create dialog when "Create New Workflow" is clicked', async () => {
    global.fetch = mockFetch({ 'GET /api/v1/agent_workflows': [] });
    render(<AgentWorkflows />);
    await waitFor(() => screen.getByText(/No workflows yet/i));

    fireEvent.click(screen.getAllByRole('button', { name: /Create New Workflow/i })[0]);
    expect(screen.getByRole('dialog')).toBeInTheDocument();
    expect(screen.getByLabelText(/Name/i)).toBeInTheDocument();
  });

  it('creates a workflow through the dialog', async () => {
    const created = { ...WORKFLOW, id: 2, name: 'New Bot', execution_count: 0 };
    global.fetch = mockFetch({
      'GET /api/v1/agent_workflows': [],
      'POST /api/v1/agent_workflows': () =>
        Promise.resolve({ ok: true, status: 201, json: () => Promise.resolve(created) }),
    });

    render(<AgentWorkflows />);
    await waitFor(() => screen.getByText(/No workflows yet/i));

    fireEvent.click(screen.getAllByRole('button', { name: /Create New Workflow/i })[0]);
    fireEvent.change(screen.getByLabelText(/Name/i), { target: { value: 'New Bot' } });
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: /^Save$/i }));
    });

    await waitFor(() => expect(screen.getByText('New Bot')).toBeInTheDocument());
  });

  it('toggles a workflow active state optimistically', async () => {
    let toggleCalled = false;
    global.fetch = mockFetch({
      'GET /api/v1/agent_workflows': [WORKFLOW],
      'GET /api/v1/agent_workflows/1/executions': EXECUTIONS,
      'PATCH /api/v1/agent_workflows/1/toggle': () => {
        toggleCalled = true;
        return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({ id: 1, active: false }) });
      },
    });

    render(<AgentWorkflows />);
    await waitFor(() => screen.getByText('Auto-SEO Enrichment'));

    const toggle = screen.getAllByRole('switch')[0];
    await act(async () => { fireEvent.click(toggle); });
    await waitFor(() => expect(toggleCalled).toBe(true));
  });

  it('shows telemetry entries in the sidebar', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/agent_workflows': [WORKFLOW],
      'GET /api/v1/agent_workflows/1/executions': EXECUTIONS,
    });

    render(<AgentWorkflows />);
    await waitFor(() =>
      expect(screen.getByText('Mapped 4 tags to summer_hero.jpg')).toBeInTheDocument());
  });

  it('displays an error alert when the workflows fetch fails', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/agent_workflows': () =>
        Promise.resolve({ ok: false, status: 500, json: () => Promise.resolve({ error: 'Server error' }) }),
    });

    render(<AgentWorkflows />);
    await waitFor(() => expect(screen.getByText(/Server error/i)).toBeInTheDocument());
  });
});


