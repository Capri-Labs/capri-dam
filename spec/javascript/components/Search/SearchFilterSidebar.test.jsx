import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));

import SearchFilterSidebar from '../../../../app/javascript/components/Search/SearchFilterSidebar';

const baseFilters = {
  mime_group: '', modified_within: '', file_size_group: '', publish_status: '', approved_status: '',
  orientation: '', style: '', video_format: '', video_codec: '', video_height_min: '', video_height_max: '',
  video_width_min: '', video_width_max: '', video_bitrate_min: '', video_bitrate_max: '',
  audio_codec: '', audio_bitrate_min: '', audio_bitrate_max: '',
};

describe('SearchFilterSidebar', () => {
  beforeEach(() => localStorage.clear());

  it('persists collapsed state and expands again', () => {
    const setItemSpy = jest.spyOn(Storage.prototype, 'setItem');
    render(<SearchFilterSidebar filters={baseFilters} activeFilterCount={0} onFilterChange={jest.fn()} onReset={jest.fn()} />);
    fireEvent.click(screen.getByLabelText('search.filters.collapse'));
    expect(setItemSpy).toHaveBeenCalled();
    fireEvent.click(screen.getAllByLabelText('search.filters.expand')[1]);
    expect(screen.getByText('search.filters.title')).toBeInTheDocument();
  });

  it('toggles mime filter chips and reset button', () => {
    const onFilterChange = jest.fn();
    const onReset = jest.fn();
    render(<SearchFilterSidebar filters={baseFilters} activeFilterCount={2} onFilterChange={onFilterChange} onReset={onReset} />);
    fireEvent.click(screen.getByText('search.filters.mime.images'));
    expect(onFilterChange).toHaveBeenCalledWith(expect.objectContaining({ mime_group: 'images' }));
    fireEvent.click(screen.getAllByLabelText('search.filters.reset')[0]);
    expect(onReset).toHaveBeenCalled();
  });

  it('updates range filters', () => {
    const onFilterChange = jest.fn();
    render(<SearchFilterSidebar filters={baseFilters} activeFilterCount={0} onFilterChange={onFilterChange} onReset={jest.fn()} />);
    fireEvent.click(screen.getByText('search.filters.video'));
    fireEvent.change(screen.getAllByLabelText('search.filters.min')[0], { target: { value: '720' } });
    expect(onFilterChange).toHaveBeenLastCalledWith(expect.objectContaining({ video_height_min: '720' }));
  });
});
