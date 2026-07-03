import React from 'react';
import { render, screen } from '@testing-library/react';
import i18n from 'i18next';
import AssetGrid from '../../../../app/javascript/components/Folders/AssetGrid';

beforeAll(() => {
  i18n.addResourceBundle('en', 'translation', {
    folders: {
      filter: { published: 'Published' },
      ai: { title: 'AI Analysis' },
      duplicates: { title: 'Find Duplicates' },
    },
  }, true, true);
});

const baseProps = {
  viewMode: 'default',
  selectedItems: { assets: [] },
  toggleSelection: jest.fn(),
  setSelectedAsset: jest.fn(),
  onPinClick: jest.fn(),
  onFindDuplicates: jest.fn(),
  onAiAnalysis: jest.fn(),
  gridSize: 'medium',
};

describe('AssetGrid preview rendering', () => {
  it('uses the flattened preview_url for a PSD instead of the raw file url', () => {
    const assets = [{
      id: '1',
      title: 'Design.psd',
      content_type: 'image/vnd.adobe.photoshop',
      url: '/api/v1/assets/local/uuid-psd',
      preview_url: '/api/v1/assets/local/uuid-psd?variant=preview',
      status: 'ready',
    }];
    render(<AssetGrid assets={assets} {...baseProps} />);
    const img = screen.getByRole('img', { name: 'Design.psd' });
    expect(img.getAttribute('src')).toContain('/api/v1/assets/local/uuid-psd?variant=preview');
    // A pre-existing query string must be extended with & (not a second ?).
    expect(img.getAttribute('src')).toContain('&w=640');
  });

  it('falls back to the asset url when no preview is available', () => {
    const assets = [{
      id: '2',
      title: 'Photo.jpg',
      content_type: 'image/jpeg',
      url: '/api/v1/assets/local/uuid-jpg',
      status: 'ready',
    }];
    render(<AssetGrid assets={assets} {...baseProps} />);
    const img = screen.getByRole('img', { name: 'Photo.jpg' });
    expect(img.getAttribute('src')).toContain('/api/v1/assets/local/uuid-jpg?w=640');
  });

  it('renders the generated preview thumbnail for a non-image document (PDF)', () => {
    const assets = [{
      id: '3',
      title: 'Brochure.pdf',
      content_type: 'application/pdf',
      url: '/api/v1/assets/local/uuid-pdf',
      preview_url: '/api/v1/assets/local/uuid-pdf?variant=preview',
      properties: { content_type: 'application/pdf', preview_storage_path: 'uuid/v1_preview.png' },
      status: 'ready',
    }];
    render(<AssetGrid assets={assets} {...baseProps} />);
    const img = screen.getByRole('img', { name: 'Brochure.pdf' });
    expect(img.getAttribute('src')).toContain('/api/v1/assets/local/uuid-pdf?variant=preview');
  });

  it('does not render an <img> for a document without a generated preview', () => {
    const assets = [{
      id: '4',
      title: 'Report.pdf',
      content_type: 'application/pdf',
      url: '/api/v1/assets/local/uuid-nopreview',
      properties: { content_type: 'application/pdf' },
      status: 'ready',
    }];
    render(<AssetGrid assets={assets} {...baseProps} />);
    expect(screen.queryByRole('img', { name: 'Report.pdf' })).toBeNull();
  });
});
