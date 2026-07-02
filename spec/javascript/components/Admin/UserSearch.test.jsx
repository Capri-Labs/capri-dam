import React from 'react';
import { render, screen, waitFor, fireEvent, act } from '@testing-library/react';

const mockApiFetch = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/utils/adminUtils', () => ({
  apiFetch: (...args) => mockApiFetch(...args),
}));

import UserSearch from '../../../../app/javascript/components/Admin/UserSearch';

describe('UserSearch', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    mockApiFetch.mockReset();
  });

  afterEach(() => {
    jest.runOnlyPendingTimers();
    jest.useRealTimers();
  });

  it('renders the input field', () => {
    render(<UserSearch onSelect={jest.fn()} />);
    expect(screen.getByPlaceholderText('Search by name or email…')).toBeInTheDocument();
  });

  it('searches and calls onSelect when a result is chosen', async () => {
    const onSelect = jest.fn();
    mockApiFetch.mockResolvedValue({
      users: [{ id: 1, display_name: 'Alice Admin', email: 'alice@example.com' }],
    });

    render(<UserSearch onSelect={onSelect} />);

    const input = screen.getByPlaceholderText('Search by name or email…');
    fireEvent.change(input, { target: { value: 'al' } });

    act(() => {
      jest.advanceTimersByTime(300);
    });

    await waitFor(() => expect(mockApiFetch).toHaveBeenCalledWith('/admin/users.json?search=al'));
    fireEvent.click(await screen.findByText('Alice Admin'));

    expect(onSelect).toHaveBeenCalledWith(expect.objectContaining({ id: 1, email: 'alice@example.com' }));
  });

  it('shows the empty state when no users are found', async () => {
    mockApiFetch.mockResolvedValue({ users: [] });

    render(<UserSearch onSelect={jest.fn()} />);

    const input = screen.getByPlaceholderText('Search by name or email…');
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: 'zz' } });

    await act(async () => {
      jest.advanceTimersByTime(300);
      await Promise.resolve();
    });

    await waitFor(() => expect(mockApiFetch).toHaveBeenCalledWith('/admin/users.json?search=zz'));
    // noOptionsText renders once dropdown opens with empty results
    expect(screen.getByText('No users found')).toBeInTheDocument();
  });
});
