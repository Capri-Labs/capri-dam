import React from 'react';
import { render, screen, waitFor, fireEvent, within } from '@testing-library/react';
import i18n from 'i18next';
import en from '../../../../../app/javascript/i18n/locales/en.json';
import ObservabilityTab from '../../../../../app/javascript/components/Admin/SystemStatus/ObservabilityTab';

const mockNotify = jest.fn();
jest.mock('../../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

// Load the real English bundle rather than stub strings, so a key renamed in
// the component but not in en.json fails here instead of silently rendering
// its own dotted key path to the user.
i18n.addResourceBundle('en', 'translation', en, true, true);

const diagnostics = {
  generated_at: '2026-09-09T08:00:00Z',
  app_server: { status: 'healthy', environment: 'production', ruby_version: '4.0.6', rails_version: '8.1.3', uptime: 'up 3 days' },
  database: {
    status: 'healthy', latency_ms: 1.2, adapter: 'PostgreSQL', server_version: '14.24',
    pool_size: 5, active_connections: 1, idle_connections: 4, pool_utilisation_percent: 20.0,
    waiting: 0, size_bytes: 54644059, longest_query_seconds: 0.0,
  },
  cache_queue: { status: 'healthy', queue_depth: 6, processed: 1977, failed: 1040, active_workers: 2, processes: 1, redis_version: '7.2.4' },
  storage_backend: { status: 'healthy', provider: 'DiskService', latency_ms: 0.84, blob_count: 255, stored_bytes: 70810891 },
  runtime: {
    status: 'healthy', hostname: 'node-a', pid: 4242, booted_at: '2026-09-06T08:00:00Z',
    uptime_seconds: 259200, revision: 'abc123def456', time_zone: 'Etc/UTC',
    heap_live_objects: 591175, gc_major_count: 6, threads: 4,
  },
  queues: {
    status: 'degraded',
    queues: [
      { name: 'webhooks', size: 6, latency_seconds: 183750.8, paused: false, status: 'degraded' },
      { name: 'default', size: 0, latency_seconds: 0.0, paused: false, status: 'healthy' },
    ],
    retry_size: 1, scheduled_size: 0, dead_size: 168, processed: 1977, failed: 1040, busy: 2,
    processes: [{ hostname: 'node-a', pid: 6607, concurrency: 25, busy: 2, queues: ['default'] }],
  },
  redis: {
    status: 'healthy', version: '7.2.4', used_memory: '2.1M', used_memory_peak: '3.4M',
    evicted_keys: 0, connected_clients: 9, uptime_days: 3, hit_rate_percent: 98.2,
  },
  content_pipeline: {
    status: 'degraded', total_assets: 169, by_status: { ready: 141, in_review: 19, failed: 9 },
    stuck_processing: 2, ingested_last_24h: 0, in_bin: 6, quarantined: 0,
  },
  preservation: {
    status: 'offline', coverage_percent: 42.5, verifiable: 146, unverifiable: 3,
    never_checked: 84, due_now: 84, oldest_check_at: null, last_run_at: '2026-09-08T04:00:00Z',
    checks_last_24h: 50, failing_last_30d: 2, by_status: { passed: 60, failed: 2 },
    high_risk_formats: 4, medium_risk_formats: 39, distinct_formats: 24,
  },
};

function mockFetchOnce(payload) {
  global.fetch = jest.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve(payload) }));
}

describe('ObservabilityTab', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockFetchOnce(diagnostics);
  });

  it('renders every diagnostic section', async () => {
    render(<ObservabilityTab />);

    expect(await screen.findByText('Background job queues')).toBeInTheDocument();
    expect(screen.getByText('Fixity & preservation')).toBeInTheDocument();
    expect(screen.getByText('Datastores')).toBeInTheDocument();
    expect(screen.getByText('Runtime & release')).toBeInTheDocument();
    // Also a summary card label, hence more than one match.
    expect(screen.getAllByText('Content pipeline').length).toBeGreaterThan(0);
  });

  it('lists each queue with its own latency, not just an aggregate depth', async () => {
    render(<ObservabilityTab />);

    const row = (await screen.findByText('webhooks')).closest('tr');
    // 183750s ≈ 2 days — the kind of stall a single "6 enqueued" total hides.
    expect(within(row).getByText('2d 3h')).toBeInTheDocument();
  });

  it('surfaces the dead set, which no aggregate reports', async () => {
    render(<ObservabilityTab />);

    const dead = (await screen.findByText('Dead')).closest('div');
    expect(within(dead).getByText('168')).toBeInTheDocument();
  });

  it('shows fixity coverage as a percentage', async () => {
    render(<ObservabilityTab />);

    // Rendered twice: once as the summary card headline, once above the bar.
    expect(await screen.findAllByText('42.5%')).toHaveLength(2);
    expect(screen.getByText('Verified coverage')).toBeInTheDocument();
  });

  it('reports assets stuck in processing', async () => {
    render(<ObservabilityTab />);

    const stuck = (await screen.findByText('Stuck processing')).closest('div');
    expect(within(stuck).getByText('2')).toBeInTheDocument();
  });

  it('renders a failed section as a warning instead of blanking the page', async () => {
    mockFetchOnce({ ...diagnostics, preservation: { status: 'error', error: 'PG::ConnectionBad' } });

    render(<ObservabilityTab />);

    expect(await screen.findByText(/PG::ConnectionBad/)).toBeInTheDocument();
    // The rest of the page still rendered.
    expect(screen.getByText('Background job queues')).toBeInTheDocument();
  });

  it('refetches on demand', async () => {
    render(<ObservabilityTab />);
    await screen.findByText('Background job queues');

    fireEvent.click(screen.getByRole('button', { name: /Refresh vitals/i }));

    await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(2));
  });

  // Regression: `t` from useTranslation is not referentially stable, so a
  // fetch callback that depended on it re-armed the mount effect on every
  // render — an unbounded request loop against an endpoint whose storage probe
  // performs a real write, read and delete each time.
  it('fetches exactly once on mount and does not refetch on re-render', async () => {
    const { rerender } = render(<ObservabilityTab />);
    await screen.findByText('Background job queues');

    rerender(<ObservabilityTab />);
    rerender(<ObservabilityTab />);

    await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(1));
  });

  it('does not poll until auto-refresh is switched on', async () => {
    jest.useFakeTimers();
    try {
      render(<ObservabilityTab />);
      jest.advanceTimersByTime(120000);
      expect(global.fetch).toHaveBeenCalledTimes(1);
    } finally {
      jest.useRealTimers();
    }
  });

  it('asks for confirmation before restarting the application server', async () => {
    window.confirm = jest.fn(() => false);
    render(<ObservabilityTab />);
    await screen.findByText('Background job queues');

    fireEvent.click(screen.getByRole('button', { name: /Initiate application reload/i }));

    expect(window.confirm).toHaveBeenCalled();
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });
});
