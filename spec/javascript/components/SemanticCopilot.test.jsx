import React from 'react';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import SemanticCopilot from '../../../app/javascript/components/Admin/Intelligence/SemanticCopilot';

// ── helpers ──────────────────────────────────────────────────────────────────

function mockFetch(routes) {
  return jest.fn((url, opts) => {
    const match = Object.keys(routes).find((k) => url.startsWith(k));
    const handler = match ? routes[match] : null;
    if (!handler) return Promise.resolve({ ok: false, status: 404, json: () => Promise.resolve({}) });
    if (typeof handler === 'function') return handler(opts);
    return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(handler) });
  });
}

const ASSET_RESULT = {
  id: 42,
  title: 'Beach Hero',
  original_filename: 'beach_hero.jpg',
  status: 'ready',
  content_type: 'image/jpeg',
  file_size: 2097152,
  width: 3200,
  height: 2400,
  folder_name: 'Summer 2025',
  folder_id: 7,
  tags: ['beach', 'summer', 'blue'],
  description: 'A beautiful beach shot.',
  campaign: 'Summer',
  url: 'http://localhost:3000/api/v1/assets/local/abc-123',
  similarity_score: 0.87,
};

const SEARCH_RESPONSE = {
  query: 'beach photo',
  count: 1,
  results: [ASSET_RESULT],
};

// ── tests ─────────────────────────────────────────────────────────────────────

describe('<SemanticCopilot />', () => {
  beforeEach(() => {
    jest.spyOn(document, 'querySelector').mockImplementation((sel) => {
      if (sel === '[name="csrf-token"]') return { content: 'test-csrf' };
      return null;
    });
    // Clear sessionStorage between tests
    sessionStorage.clear();
  });

  afterEach(() => jest.restoreAllMocks());

  it('renders the title and greeting on mount', () => {
    global.fetch = mockFetch({});
    render(<SemanticCopilot />);
    // Title appears in the header (may match multiple nodes via i18n)
    expect(screen.getAllByText(/Semantic Copilot/i).length).toBeGreaterThan(0);
  });

  it('shows suggested prompts on initial render', () => {
    global.fetch = mockFetch({});
    render(<SemanticCopilot />);
    expect(screen.getByText(/Try asking/i)).toBeInTheDocument();
    expect(screen.getByText(/Summer campaign visuals/i)).toBeInTheDocument();
  });

  it('shows the content-type filter buttons', () => {
    global.fetch = mockFetch({});
    render(<SemanticCopilot />);
    expect(screen.getByRole('group', { name: /Filter by type/i })).toBeInTheDocument();
  });

  it('submits a query and displays asset results', async () => {
    global.fetch = mockFetch({ '/api/v1/copilot/search': SEARCH_RESPONSE });
    render(<SemanticCopilot />);

    const input = screen.getByRole('textbox', { name: /Search query/i });
    fireEvent.change(input, { target: { value: 'beach photo' } });
    const sendBtn = screen.getByRole('button', { name: /Send/i });
    await act(async () => { fireEvent.click(sendBtn); });

    await waitFor(() => expect(screen.getByText('Beach Hero')).toBeInTheDocument());
    // Folder name is rendered with a leading 📁 emoji, so match flexibly.
    expect(screen.getByText((content) => content.includes('Summer 2025'))).toBeInTheDocument();
    expect(screen.getByText('87%')).toBeInTheDocument();
  });

  it('renders "View in DAM" link with correct href', async () => {
    global.fetch = mockFetch({ '/api/v1/copilot/search': SEARCH_RESPONSE });
    render(<SemanticCopilot />);

    const input = screen.getByRole('textbox', { name: /Search query/i });
    fireEvent.change(input, { target: { value: 'beach' } });
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: /Send/i })); });

    await waitFor(() => screen.getByText('Beach Hero'));
    const link = screen.getByRole('link', { name: /View in DAM/i });
    expect(link).toHaveAttribute('href', '/assets?id=42');
    expect(link).toHaveAttribute('target', '_blank');
  });

  it('shows similarity bar when similarity_score is provided', async () => {
    global.fetch = mockFetch({ '/api/v1/copilot/search': SEARCH_RESPONSE });
    render(<SemanticCopilot />);

    const input = screen.getByRole('textbox', { name: /Search query/i });
    fireEvent.change(input, { target: { value: 'beach' } });
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: /Send/i })); });

    await waitFor(() => screen.getByText('87%'));
    // MUI LinearProgress exposes role="progressbar"
    expect(screen.getAllByRole('progressbar').length).toBeGreaterThan(0);
  });

  it('shows an error alert when the API returns a non-ok response', async () => {
    global.fetch = mockFetch({
      '/api/v1/copilot/search': () =>
        Promise.resolve({ ok: false, status: 503, json: () => Promise.resolve({ error: 'AI Gateway unavailable' }) }),
    });

    render(<SemanticCopilot />);
    const input = screen.getByRole('textbox', { name: /Search query/i });
    fireEvent.change(input, { target: { value: 'test' } });
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: /Send/i })); });

    await waitFor(() => expect(screen.getAllByText(/AI Gateway unavailable/i).length).toBeGreaterThan(0));
  });

  it('sends a query when a suggestion is clicked', async () => {
    global.fetch = mockFetch({ '/api/v1/copilot/search': { query: 'summer', count: 0, results: [] } });
    render(<SemanticCopilot />);

    const suggestion = screen.getByRole('button', { name: /Summer campaign visuals/i });
    await act(async () => { fireEvent.click(suggestion); });

    await waitFor(() =>
      expect(global.fetch).toHaveBeenCalledWith(
        '/api/v1/copilot/search',
        expect.objectContaining({ method: 'POST' }),
      ),
    );
  });

  it('clears conversation and results when Clear button is clicked', async () => {
    global.fetch = mockFetch({ '/api/v1/copilot/search': SEARCH_RESPONSE });
    render(<SemanticCopilot />);

    // Do a search first
    const input = screen.getByRole('textbox', { name: /Search query/i });
    fireEvent.change(input, { target: { value: 'beach' } });
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: /Send/i })); });
    await waitFor(() => screen.getByText('Beach Hero'));

    // Now clear
    const clearBtn = screen.getByRole('button', { name: /Clear conversation/i });
    fireEvent.click(clearBtn);
    expect(screen.queryByText('Beach Hero')).not.toBeInTheDocument();
  });
});

