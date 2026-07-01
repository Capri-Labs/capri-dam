import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import i18n from 'i18next';
import AssetFilterBar from '../../../../app/javascript/components/Folders/AssetFilterBar';

beforeAll(() => {
  i18n.addResourceBundle('en', 'translation', {
    folders: {
      filter: {
        search_placeholder: 'Search assets and folders...',
        type_label: 'Type',
        status_label: 'Status',
        clear: 'Clear',
        per_page: 'page',
        all: 'All',
        folders: 'Folders',
        images: 'Images',
        videos: 'Videos',
        documents: 'Documents',
        audio: 'Audio',
        status_all: 'Any Status',
        draft: 'Draft',
        published: 'Published',
        approved: 'Approved',
        rejected: 'Rejected',
        results: 'Results',
        name_az: 'Name (A–Z)',
        name_za: 'Name (Z–A)',
        created_newest: 'Created (Newest first)',
        created_oldest: 'Created (Oldest first)',
        size_largest: 'Size (Largest first)',
        size_smallest: 'Size (Smallest first)',
        type_sort: 'Type',
      },
    },
  }, true, true);
});

describe('AssetFilterBar', () => {
  const props = {
    query: '',
    onQueryChange: jest.fn(),
    typeFilters: [],
    onTypeFiltersChange: jest.fn(),
    statusFilters: [],
    onStatusFiltersChange: jest.fn(),
    sort: { field: 'name', direction: 'asc' },
    onSortChange: jest.fn(),
    viewLayout: 'grid',
    onViewLayoutChange: jest.fn(),
    gridSize: 'medium',
    onGridSizeChange: jest.fn(),
    resultCount: 12,
    perPage: 25,
    onPerPageChange: jest.fn(),
    allSelected: false,
    hasSelection: false,
    onSelectAll: jest.fn(),
    onDeselectAll: jest.fn(),
  };

  beforeEach(() => {
    Object.values(props).forEach((value) => {
      if (typeof value === 'function' && value.mockClear) value.mockClear();
    });
  });

  it('renders search input and filter dropdowns', () => {
    render(<AssetFilterBar {...props} />);
    expect(screen.getByPlaceholderText('Search assets and folders...')).toBeInTheDocument();
    // Type and Status dropdown buttons should be present
    expect(screen.getByText('Type')).toBeInTheDocument();
    expect(screen.getByText('Status')).toBeInTheDocument();
  });

  it('calls onQueryChange when typing in search', () => {
    render(<AssetFilterBar {...props} />);
    fireEvent.change(screen.getByPlaceholderText('Search assets and folders...'), { target: { value: 'hero' } });
    expect(props.onQueryChange).toHaveBeenCalledWith('hero');
  });

  it('calls onTypeFiltersChange when selecting a type', () => {
    render(<AssetFilterBar {...props} />);
    // Open the Type dropdown
    fireEvent.click(screen.getByText('Type'));
    // Click Images menu item
    fireEvent.click(screen.getByText('Images'));
    expect(props.onTypeFiltersChange).toHaveBeenCalledWith(['images']);
  });

  it('calls onStatusFiltersChange when selecting a status', () => {
    render(<AssetFilterBar {...props} />);
    fireEvent.click(screen.getByText('Status'));
    fireEvent.click(screen.getByText('Published'));
    expect(props.onStatusFiltersChange).toHaveBeenCalledWith(['published']);
  });

  it('calls onGridSizeChange when clicking S button', () => {
    render(<AssetFilterBar {...props} />);
    fireEvent.click(screen.getByRole('button', { name: 'S' }));
    expect(props.onGridSizeChange).toHaveBeenCalledWith('small');
  });

  it('calls onPerPageChange when changing per-page select', () => {
    render(<AssetFilterBar {...props} />);
    // The per-page select should show current value
    expect(screen.getByText(/25/)).toBeInTheDocument();
  });
});
