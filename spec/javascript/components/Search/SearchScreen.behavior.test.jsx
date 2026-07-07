import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';

const mockClipboardWriteText = jest.fn();
const stableT = (key) => key;

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: stableT }),
  Trans: ({ i18nKey }) => i18nKey,
}));

import SearchScreen from '../../../../app/javascript/components/Search/SearchScreen';

function jsonResponse(data, ok = true) {
  return Promise.resolve({ ok, json: () => Promise.resolve(data) });
}

function setUrl(path) {
  window.history.pushState({}, '', `http://localhost${path}`);
}

describe('SearchScreen behavior', () => {
  const searchResponse = {
    results: [{ uuid: 'asset-1', title: 'Search Asset', content_type: 'image/jpeg', thumb_url: 'http://example.com/search.jpg', status: 'active', size: '1 MB', width: 800, height: 600, updated_at: '2025-01-01T00:00:00Z', metadata: { brand: 'Acme' } }],
    meta: { total_found: 2, total_pages: 2, facets: { metadata_fields: {} } },
  };

  beforeEach(() => {
    jest.clearAllMocks();
    global.fetch = jest.fn((url) => String(url).includes('/api/v1/search') ? jsonResponse(searchResponse) : jsonResponse({}));
    navigator.clipboard.writeText = mockClipboardWriteText;
    window.scrollTo = jest.fn();
    const _csrfMeta = document.head.querySelector('meta[name="csrf-token"]') || (() => { const m = document.createElement('meta'); m.name = 'csrf-token'; document.head.appendChild(m); return m; })(); _csrfMeta.content = 'token';
    setUrl('/search?q=logo&page=1');
  });

  it('fetches results, shares the current url and runs quick search', async () => {
    render(<SearchScreen />);
    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(expect.stringContaining('/api/v1/search?q=logo'), expect.any(Object)));

    const shareButton = document.querySelector('[data-testid="IosShareIcon"]')?.closest('button');
    fireEvent.click(shareButton);
    expect(mockClipboardWriteText).toHaveBeenCalled();

    fireEvent.click(screen.getByText('search.quickSearches.documents'));
    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(expect.stringContaining('mime_group=documents'), expect.any(Object)));
  });

  it('forwards the mode query param from the URL to the backend request', async () => {
    setUrl('/search?q=sunset&mode=visual&page=1');
    render(<SearchScreen />);
    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(expect.stringContaining('mode=visual'), expect.any(Object)));
  });

  it('shows a semantic match chip and fallback notice based on response meta', async () => {
    global.fetch = jest.fn(() => jsonResponse({
      ...searchResponse,
      meta: { ...searchResponse.meta, mode: 'visual', result_type: 'semantic', semantic_fallback: true },
    }));
    setUrl('/search?q=sunset&mode=visual&page=1');
    render(<SearchScreen />);

    expect(await screen.findByText('search.mode.semantic')).toBeInTheDocument();
    expect(screen.getByText('search.semanticFallback')).toBeInTheDocument();
  });

  describe('navigating to an asset from a result card', () => {
    let mockOpen;

    beforeEach(() => {
      mockOpen = jest.fn();
      window.open = mockOpen;
    });

    it('opens the /assets?id=UUID deep-link in a new tab (grid view) when the result has no folder_id', async () => {
      render(<SearchScreen />);
      await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(expect.stringContaining('/api/v1/search'), expect.any(Object)));
      const card = await screen.findByText('Search Asset');
      fireEvent.click(card);

      expect(mockOpen).toHaveBeenCalledWith('/assets?id=asset-1', '_blank', 'noopener');
    });

    it('opens the /assets?id=UUID deep-link in a new tab (list view) when the result has no folder_id', async () => {
      render(<SearchScreen />);
      await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(expect.stringContaining('/api/v1/search'), expect.any(Object)));
      await screen.findByText('Search Asset');

      const listViewButton = document.querySelector('[data-testid="ViewListIcon"]')?.closest('button');
      fireEvent.click(listViewButton);

      const card = await screen.findByText('Search Asset');
      fireEvent.click(card);

      expect(mockOpen).toHaveBeenCalledWith('/assets?id=asset-1', '_blank', 'noopener');
    });

    it('opens /folders?folder=<id>&id=<id> in a new tab when the result carries a folder_id, so the search results tab is left untouched', async () => {
      global.fetch = jest.fn((url) => String(url).includes('/api/v1/search')
        ? jsonResponse({
          ...searchResponse,
          results: [ { ...searchResponse.results[0], folder_id: 'folder-9' } ],
        })
        : jsonResponse({}));

      render(<SearchScreen />);
      await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(expect.stringContaining('/api/v1/search'), expect.any(Object)));
      const card = await screen.findByText('Search Asset');
      fireEvent.click(card);

      expect(mockOpen).toHaveBeenCalledWith('/folders?folder=folder-9&id=asset-1', '_blank', 'noopener');
    });
  });
});
