import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';

const mockClipboardWriteText = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
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
});
