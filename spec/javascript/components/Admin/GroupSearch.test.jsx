import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));

import GroupSearch from '../../../../app/javascript/components/Admin/GroupSearch';

describe('GroupSearch', () => {
  const groups = [
    { id: 1, name: 'Editors', slug: 'editors' },
    { id: 2, name: 'Reviewers', slug: 'reviewers' },
  ];

  it('renders the search field', () => {
    render(<GroupSearch groups={groups} onSelect={jest.fn()} />);
    expect(screen.getByPlaceholderText('Search groups…')).toBeInTheDocument();
  });

  it('fires callbacks when a group is selected', async () => {
    const onSelect = jest.fn();
    render(<GroupSearch groups={groups} onSelect={onSelect} />);

    const input = screen.getByRole('combobox');
    fireEvent.mouseDown(input);
    fireEvent.click(await screen.findByText('Editors'));

    expect(onSelect).toHaveBeenCalledWith(expect.objectContaining({ id: 1, name: 'Editors' }));
  });
});
