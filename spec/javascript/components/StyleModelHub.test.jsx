import React from 'react';
import { render, screen, fireEvent, waitFor, act, cleanup } from '@testing-library/react';
import StyleModelHub from '../../../app/javascript/components/Admin/Intelligence/StyleModelHub';

// ─── i18n mock ────────────────────────────────────────────────────────────────
jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key, opts) => opts?.defaultValue ?? key,
  }),
}));

// ─── fetch mock helpers ───────────────────────────────────────────────────────
const MODEL_CONFIGS = {
  total: 2,
  configs: [
    { id: 1, name: 'GPT-4o', provider: 'openai', model_id: 'gpt-4o', capability: 'generation', enabled: true, is_default: true, health_status: 'healthy', health_latency_ms: 95, config_params: {}, metadata: {} },
    { id: 2, name: 'Embedding 3', provider: 'openai', model_id: 'text-embedding-3-small', capability: 'embedding', enabled: true, is_default: false, health_status: 'unknown', config_params: {}, metadata: {} },
  ],
};

const CAPABILITIES = {
  capabilities: ['embedding', 'generation', 'vision', 'style_transfer', 'audio'],
  providers: ['openai', 'anthropic', 'ollama', 'huggingface', 'azure_openai', 'custom'],
  health_statuses: ['healthy', 'degraded', 'unhealthy', 'unknown'],
};

const STYLE_PRESETS = {
  total: 1,
  presets: [
    { id: 10, name: 'Editorial Dark', slug: 'editorial-dark', description: 'Dark tone', active: true, is_default: false, style_params: {}, gateway_ref: null, synced_at: null, stale: false, created_by: 'admin@example.com' },
  ],
};

const BATCH_TASKS = {
  tasks: [
    { key: 'embed_regenerate', label: 'Embedding Regeneration', description: 'Regen embeddings', cost_tier: 'medium', gateway_capability: 'embedding.regenerate' },
    { key: 'style_audit', label: 'Style Audit', description: 'Audit styles', cost_tier: 'high', gateway_capability: 'style.audit' },
    { key: 'style_tag', label: 'Style Auto-Tag', description: 'Tag assets', cost_tier: 'medium', gateway_capability: 'style.tag' },
  ],
  scopes: [
    { key: 'all_images_unembedded', label: 'Images Without Embeddings', description: '' },
    { key: 'style_untagged', label: 'Assets Without Style Tags', description: '' },
  ],
};

const BATCH_JOBS = { total: 0, page: 1, per_page: 25, jobs: [] };

function mockFetch(url) {
  if (url.includes('/api/v1/ai_model_configs/capabilities')) return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(CAPABILITIES) });
  if (url.includes('/api/v1/ai_model_configs')) return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(MODEL_CONFIGS) });
  if (url.includes('/api/v1/style_presets')) return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(STYLE_PRESETS) });
  if (url.includes('/api/v1/ai_batch_jobs/task_types')) return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(BATCH_TASKS) });
  if (url.includes('/api/v1/ai_batch_jobs')) return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(BATCH_JOBS) });
  return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({}) });
}

beforeEach(() => {
  global.fetch = jest.fn(mockFetch);
  // Do NOT use document.head.innerHTML — it wipes Emotion's cached <style> nodes.
  // Instead, insert or update the CSRF meta tag surgically.
  let meta = document.querySelector('meta[name="csrf-token"]');
  if (!meta) {
    meta = document.createElement('meta');
    meta.setAttribute('name', 'csrf-token');
    document.head.appendChild(meta);
  }
  meta.setAttribute('content', 'test-token');
});

afterEach(async () => {
  await act(async () => { cleanup(); });
  jest.restoreAllMocks();
});

// ─── tests ───────────────────────────────────────────────────────────────────

describe('StyleModelHub', () => {
  it('renders the page header', async () => {
    await act(async () => { render(<StyleModelHub />); });
    expect(screen.getByText('Style & Model Hub')).toBeInTheDocument();
  });

  it('renders three tabs', async () => {
    await act(async () => { render(<StyleModelHub />); });
    expect(screen.getByText('Models')).toBeInTheDocument();
    expect(screen.getByText('Style Presets')).toBeInTheDocument();
    expect(screen.getByText('Batch Tasks')).toBeInTheDocument();
  });

  it('loads and displays model configs on the Models tab', async () => {
    await act(async () => { render(<StyleModelHub />); });
    await waitFor(() => {
      expect(screen.getByText('GPT-4o')).toBeInTheDocument();
      expect(screen.getByText('Embedding 3')).toBeInTheDocument();
    });
  });

  it('shows healthy chip for healthy model', async () => {
    await act(async () => { render(<StyleModelHub />); });
    await waitFor(() => {
      // HealthChip uses defaultValue: status (lowercase); match case-insensitively
      expect(screen.getByText(/healthy/i)).toBeInTheDocument();
    });
  });

  it('switches to Style Presets tab and shows preset card', async () => {
    await act(async () => { render(<StyleModelHub />); });
    await act(async () => {
      fireEvent.click(screen.getByText('Style Presets'));
    });
    await waitFor(() => {
      expect(screen.getByText('Editorial Dark')).toBeInTheDocument();
      expect(screen.getByText('Not synced')).toBeInTheDocument();
    });
  });

  it('switches to Batch Tasks tab and shows launch button', async () => {
    await act(async () => { render(<StyleModelHub />); });
    await act(async () => {
      fireEvent.click(screen.getByText('Batch Tasks'));
    });
    await waitFor(() => {
      expect(screen.getByText('Launch Task')).toBeInTheDocument();
    });
  });

  it('opens Add Model dialog on button click', async () => {
    await act(async () => { render(<StyleModelHub />); });
    await waitFor(() => screen.getByText('GPT-4o'));
    await act(async () => {
      fireEvent.click(screen.getByText('Add Model'));
    });
    await waitFor(() => {
      expect(screen.getByText('Add Model', { selector: 'h2, [role="dialog"] *' })).toBeInTheDocument();
    });
  });
});

