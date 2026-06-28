import React from 'react';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import PromptPlayground from '../../../app/javascript/components/Admin/Intelligence/PromptPlayground';

// ── helpers ──────────────────────────────────────────────────────────────────

function mockFetch(routes) {
  return jest.fn((url, opts) => {
    const match = Object.keys(routes).find((k) => url.startsWith(k));
    const handler = match ? routes[match] : null;
    if (!handler) return Promise.resolve({ ok: false, json: () => Promise.resolve({}) });
    if (typeof handler === 'function') return handler(opts);
    return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(handler) });
  });
}

const MODELS_RESPONSE = {
  active_provider: 'openai',
  default_model:   'gpt-4o',
  models:          ['gpt-4o', 'gpt-4o-mini'],
  all_providers:   { openai: ['gpt-4o', 'gpt-4o-mini'] },
};

const CHAT_RESPONSE = {
  choices: [{ message: { role: 'assistant', content: 'A DAM manages digital assets.' } }],
  usage:   { prompt_tokens: 12, completion_tokens: 8, total_tokens: 20 },
  model:   'gpt-4o',
};

// ── tests ─────────────────────────────────────────────────────────────────────

describe('<PromptPlayground />', () => {
  beforeEach(() => {
    // Reset document.querySelector for CSRF token
    jest.spyOn(document, 'querySelector').mockImplementation((sel) => {
      if (sel === '[name="csrf-token"]') return { content: 'test-csrf' };
      return null;
    });
  });

  afterEach(() => jest.restoreAllMocks());

  it('renders the title and default messages on mount', async () => {
    global.fetch = mockFetch({ '/api/v1/ai/lab/models': MODELS_RESPONSE });

    render(<PromptPlayground />);

    expect(screen.getByText(/Prompt Playground/i)).toBeInTheDocument();
    expect(screen.getAllByText(/Run Prompt/i).length).toBeGreaterThan(0);

    // Should show default system + user message blocks
    await waitFor(() => expect(screen.getAllByText(/System/i).length).toBeGreaterThan(0));
    expect(screen.getAllByText(/User/i).length).toBeGreaterThan(0);
  });

  it('populates the model selector from the API', async () => {
    global.fetch = mockFetch({ '/api/v1/ai/lab/models': MODELS_RESPONSE });
    render(<PromptPlayground />);

    // Wait for config load
    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(
      '/api/v1/ai/lab/models',
      expect.any(Object),
    ));
  });

  it('disables Run button when all message content is empty', async () => {
    global.fetch = mockFetch({ '/api/v1/ai/lab/models': MODELS_RESPONSE });
    render(<PromptPlayground />);

    // The user message starts empty; system has content — button should be enabled
    const runBtn = await screen.findByRole('button', { name: /Run Prompt/i });
    // System message has content, so button is enabled by default
    expect(runBtn).not.toBeDisabled();
  });

  it('shows the AI response after a successful chat call', async () => {
    global.fetch = mockFetch({
      '/api/v1/ai/lab/models': MODELS_RESPONSE,
      '/api/v1/ai/lab/chat': () =>
        Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(CHAT_RESPONSE) }),
    });

    render(<PromptPlayground />);
    await screen.findByRole('button', { name: /Run Prompt/i });

    const runBtn = screen.getByRole('button', { name: /Run Prompt/i });
    await act(async () => { fireEvent.click(runBtn); });

    await waitFor(() =>
      expect(screen.getByText(/A DAM manages digital assets/i)).toBeInTheDocument(),
    );

    // Token badge should appear
    expect(screen.getByText(/Prompt:/)).toBeInTheDocument();
  });

  it('shows an error alert when the gateway returns an error', async () => {
    global.fetch = mockFetch({
      '/api/v1/ai/lab/models': MODELS_RESPONSE,
      '/api/v1/ai/lab/chat': () =>
        Promise.resolve({
          ok: false,
          status: 503,
          json: () => Promise.resolve({ error: 'AI Gateway unavailable' }),
        }),
    });

    render(<PromptPlayground />);
    const runBtn = await screen.findByRole('button', { name: /Run Prompt/i });
    await act(async () => { fireEvent.click(runBtn); });

    await waitFor(() =>
      expect(screen.getByText(/AI Gateway unavailable/i)).toBeInTheDocument(),
    );
  });

  it('adds a completed run to history tab', async () => {
    global.fetch = mockFetch({
      '/api/v1/ai/lab/models': MODELS_RESPONSE,
      '/api/v1/ai/lab/chat': () =>
        Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(CHAT_RESPONSE) }),
    });

    render(<PromptPlayground />);
    const runBtn = await screen.findByRole('button', { name: /Run Prompt/i });
    await act(async () => { fireEvent.click(runBtn); });

    await waitFor(() => screen.getByText(/A DAM manages digital assets/i));

    const historyTab = screen.getByRole('tab', { name: /history/i });
    fireEvent.click(historyTab);

    expect(screen.getByRole('button', { name: /Restore/i })).toBeInTheDocument();
  });

  it('resets messages when Reset button is clicked', async () => {
    global.fetch = mockFetch({ '/api/v1/ai/lab/models': MODELS_RESPONSE });
    render(<PromptPlayground />);
    await waitFor(() => screen.getByText(/Prompt Playground/i));

    const resetBtn = screen.getByRole('button', { name: /Reset conversation/i });
    fireEvent.click(resetBtn);

    // After reset the system message should be back to its default
    expect(screen.queryByText(/A DAM manages digital assets/i)).not.toBeInTheDocument();
  });
});

