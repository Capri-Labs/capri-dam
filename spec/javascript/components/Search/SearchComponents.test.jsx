import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));

import AssetFilterBar from '../../../../app/javascript/components/Search/AssetFilterBar';
import SearchResultCard, { SearchResultCardSkeleton } from '../../../../app/javascript/components/Search/SearchResultCard';

function setUrl(path) {
  window.history.pushState({}, '', `http://localhost${path}`);
}

describe('Search components', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    setUrl('/search');
  });

  describe('AssetFilterBar', () => {
    it('renders facet groups and reflects current query params', () => {
      setUrl('/search?mime_group=images,documents');
      render(<AssetFilterBar facets={{ mime_group: ['images', 'documents'], status: ['approved'] }} onFilterChange={jest.fn()} />);

      expect(screen.getByText('Filters')).toBeInTheDocument();
      expect(screen.getByLabelText('images')).toBeChecked();
      expect(screen.getByLabelText('documents')).toBeChecked();
      expect(screen.getByLabelText('approved')).not.toBeChecked();
    });

    it('adds and removes values through onFilterChange', () => {
      const onFilterChange = jest.fn();
      setUrl('/search?mime_group=images');
      render(<AssetFilterBar facets={{ mime_group: ['images', 'documents'] }} onFilterChange={onFilterChange} />);

      fireEvent.click(screen.getByLabelText('documents'));
      expect(onFilterChange).toHaveBeenCalledWith('mime_group', 'images,documents');

      fireEvent.click(screen.getByLabelText('images'));
      expect(onFilterChange).toHaveBeenCalledWith('mime_group', '');
    });
  });

  describe('SearchResultCard', () => {
    const asset = {
      uuid: 'a1',
      title: 'Hero Image',
      content_type: 'image/jpeg',
      thumb_url: 'http://example.com/hero.jpg',
      status: 'approved',
      size: '2 MB',
      width: 1200,
      height: 800,
      updated_at: '2025-01-01T00:00:00Z',
      metadata: { brand: 'Acme' },
    };

    it('renders grid details and calls onClick', () => {
      const onClick = jest.fn();
      render(<SearchResultCard asset={asset} onClick={onClick} />);

      expect(screen.getByText('Hero Image')).toBeInTheDocument();
      expect(screen.getByText('Acme')).toBeInTheDocument();
      expect(screen.getByAltText('Hero Image')).toHaveAttribute('loading', 'lazy');

      fireEvent.click(screen.getByText('Hero Image'));
      expect(onClick).toHaveBeenCalledWith(asset);
    });

    it('renders list mode with fallback icon and dimensions', () => {
      const onClick = jest.fn();
      render(<SearchResultCard asset={{ ...asset, content_type: 'application/pdf', thumb_url: null }} viewMode="list" onClick={onClick} />);

      expect(screen.getByText('application/pdf')).toBeInTheDocument();
      expect(screen.getByText('1200×800')).toBeInTheDocument();
      fireEvent.click(screen.getByText('Hero Image'));
      expect(onClick).toHaveBeenCalled();
    });

    it('renders generated preview_url for special formats like PSD/TIFF/PDF', () => {
      const psdAsset = {
        ...asset,
        content_type: 'image/vnd.adobe.photoshop',
        thumb_url: null,
        preview_url: 'http://example.com/hero-preview.png',
      };
      render(<SearchResultCard asset={psdAsset} onClick={jest.fn()} />);

      expect(screen.getByAltText('Hero Image')).toHaveAttribute('src', 'http://example.com/hero-preview.png');
    });

    it('falls back to the file-type icon when the preview image fails to load', () => {
      render(<SearchResultCard asset={asset} onClick={jest.fn()} />);

      const img = screen.getByAltText('Hero Image');
      fireEvent.error(img);

      expect(screen.queryByAltText('Hero Image')).not.toBeInTheDocument();
    });

    it('renders skeleton variants', () => {
      const { rerender } = render(<SearchResultCardSkeleton />);
      expect(document.querySelectorAll('.MuiSkeleton-root').length).toBeGreaterThan(0);
      rerender(<SearchResultCardSkeleton viewMode="list" />);
      expect(document.querySelectorAll('.MuiSkeleton-root').length).toBeGreaterThan(0);
    });
  });
});
