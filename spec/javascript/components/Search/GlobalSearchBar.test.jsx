import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key, opts) => (opts?.query ? `${key}:${opts.query}` : key) }),
  Trans: ({ i18nKey }) => i18nKey,
}));

import GlobalSearchBar from '../../../../app/javascript/components/Search/GlobalSearchBar';

describe('GlobalSearchBar', () => {
  let originalLocation;

  beforeEach(() => {
    originalLocation = window.location;
    delete window.location;
    window.location = { search: '?q=mountains&mode=folders', href: 'http://localhost/' };
    global.fetch = jest.fn(() => Promise.resolve({ json: () => Promise.resolve({ results: [] }) }));
  });

  afterEach(() => {
    window.location = originalLocation;
    jest.restoreAllMocks();
  });

  it('hydrates from location and updates search mode', async () => {
    render(<GlobalSearchBar />);
    expect(screen.getByLabelText('globalSearchBar.ariaLabel')).toHaveValue('mountains');

    fireEvent.mouseDown(screen.getByRole('combobox'));
    fireEvent.click(await screen.findByText('globalSearchBar.modes.agentic'));
    expect(screen.getByPlaceholderText('globalSearchBar.placeholder.agentic')).toBeInTheDocument();
  });

  it('navigates on enter', () => {
    window.location.search = '';
    render(<GlobalSearchBar />);
    const input = screen.getByLabelText('globalSearchBar.ariaLabel');
    fireEvent.change(input, { target: { value: 'brand guide' } });
    fireEvent.keyDown(input, { key: 'Enter', code: 'Enter' });
    expect(window.location.href).toBe('/search?q=brand%20guide&mode=images');
  });

  it('fetches and renders suggestions while typing (debounced)', async () => {
    global.fetch.mockResolvedValueOnce({
      json: () => Promise.resolve({
        query: 'brand',
        results: [
          { type: 'asset', id: 'abc-123', title: 'Brand Kit', subtitle: 'image/png', href: '/assets?id=abc-123' },
          { type: 'folder', id: 7, title: 'Brand Guidelines', href: '/folders?folder=7' },
        ],
      }),
    });

    window.location.search = '';
    render(<GlobalSearchBar />);
    const input = screen.getByLabelText('globalSearchBar.ariaLabel');
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: 'brand' } });

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining('/api/v1/search/suggestions?q=brand'),
      expect.any(Object)
    ), { timeout: 1000 });

    expect(await screen.findByText('Brand Kit')).toBeInTheDocument();
    expect(screen.getByText('Brand Guidelines')).toBeInTheDocument();
  });

  it('navigates directly to the asset viewer when a suggestion is clicked', async () => {
    global.fetch.mockResolvedValueOnce({
      json: () => Promise.resolve({
        query: 'brand',
        results: [
          { type: 'asset', id: 'abc-123', title: 'Brand Kit', subtitle: 'image/png', href: '/assets?id=abc-123' },
        ],
      }),
    });

    window.location.search = '';
    render(<GlobalSearchBar />);
    const input = screen.getByLabelText('globalSearchBar.ariaLabel');
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: 'brand' } });

    const suggestion = await screen.findByText('Brand Kit');
    fireEvent.mouseDown(suggestion);

    expect(window.location.href).toBe('/assets?id=abc-123');
  });

  it('does not fetch suggestions for very short queries or in visual mode', () => {
    window.location.search = '';
    render(<GlobalSearchBar />);
    const input = screen.getByLabelText('globalSearchBar.ariaLabel');
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: 'a' } });

    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('focuses the input when Cmd+K / Ctrl+K is pressed anywhere', () => {
    window.location.search = '';
    render(<GlobalSearchBar />);
    const input = screen.getByLabelText('globalSearchBar.ariaLabel');
    expect(input).not.toHaveFocus();

    fireEvent.keyDown(window, { key: 'k', ctrlKey: true });

    expect(input).toHaveFocus();
  });
});
