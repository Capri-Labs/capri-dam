import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));

import GlobalSearchBar from '../../../../app/javascript/components/Search/GlobalSearchBar';

describe('GlobalSearchBar', () => {
  let originalLocation;

  beforeEach(() => {
    originalLocation = window.location;
    delete window.location;
    window.location = { search: '?q=mountains&mode=folders', href: 'http://localhost/' };
  });

  afterEach(() => {
    window.location = originalLocation;
  });

  it('hydrates from location and updates search mode', async () => {
    render(<GlobalSearchBar />);
    expect(screen.getByLabelText('global search')).toHaveValue('mountains');

    fireEvent.mouseDown(screen.getByRole('combobox'));
    fireEvent.click(await screen.findByText('Ask AI Agent'));
    expect(screen.getByPlaceholderText('E.g., Find summer photos without logos...')).toBeInTheDocument();
  });

  it('navigates on enter', () => {
    window.location.search = '';
    render(<GlobalSearchBar />);
    const input = screen.getByLabelText('global search');
    fireEvent.change(input, { target: { value: 'brand guide' } });
    fireEvent.keyDown(input, { key: 'Enter', code: 'Enter' });
    expect(window.location.href).toBe('/search?q=brand%20guide&mode=images');
  });
});
