import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
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

  it('shows a Processing placeholder for a pending asset instead of attempting to load a broken image', () => {
    const assets = [{
      id: '5',
      title: 'Uploading.jpg',
      content_type: 'image/jpeg',
      url: '/api/v1/assets/local/uuid-pending',
      status: 'pending',
    }];
    render(<AssetGrid assets={assets} {...baseProps} />);
    // No <img> should be attempted while the worker hasn't finished processing.
    expect(screen.queryByRole('img', { name: 'Uploading.jpg' })).toBeNull();
    expect(screen.getAllByText(/processing/i).length).toBeGreaterThan(0);
  });

  it('shows a Processing placeholder for an asset whose status is "processing"', () => {
    const assets = [{
      id: '6',
      title: 'Encoding.mp4',
      content_type: 'video/mp4',
      url: '/api/v1/assets/local/uuid-processing',
      status: 'processing',
    }];
    render(<AssetGrid assets={assets} {...baseProps} />);
    expect(screen.getAllByText(/processing/i).length).toBeGreaterThan(0);
  });

  it('falls back to a broken-image placeholder when the preview URL fails to load', () => {
    const assets = [{
      id: '7',
      title: 'Missing.jpg',
      content_type: 'image/jpeg',
      url: '/api/v1/assets/local/uuid-missing',
      status: 'ready',
    }];
    render(<AssetGrid assets={assets} {...baseProps} />);
    const img = screen.getByRole('img', { name: 'Missing.jpg' });
    fireEvent.error(img);
    expect(screen.queryByRole('img', { name: 'Missing.jpg' })).toBeNull();
    expect(screen.getByText(/preview.*unavailable|previewUnavailable/i)).toBeInTheDocument();
  });
});
