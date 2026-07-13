import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';

const mockNotify = jest.fn();
const mockApiFetch = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key, opts) => {
      if (opts && typeof opts === 'object' && 'defaultValue' in opts) return opts.defaultValue;
      return key;
    },
  }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

jest.mock('../../../../app/javascript/utils/adminUtils', () => ({
  apiFetch: (...args) => mockApiFetch(...args),
  isSystemGroup: (group) => group.is_system,
  SYSTEM_SLUGS: { EVERYONE: 'everyone', ADMINS: 'administrators', SUPER_ADMINS: 'super-administrators' },
}));

jest.mock('../../../../app/javascript/components/Admin/GroupOverlay', () => ({ open, group }) => (
  open ? <div>GroupOverlay:{group?.name}</div> : null
));

import UserGroupsManager from '../../../../app/javascript/components/Admin/UserGroupsManager';

describe('UserGroupsManager', () => {
  beforeEach(() => {
    mockApiFetch.mockReset();
    mockApiFetch.mockResolvedValue({
      user_groups: [
        { id: 1, name: 'Everyone', slug: 'everyone', member_count: 5, is_system: true },
        { id: 2, name: 'Editors', slug: 'editors', member_count: 2, is_system: false },
      ],
    });
  });

  it('renders without crashing', async () => {
    render(<UserGroupsManager isAdmin currentUserId={1} />);
    expect(screen.getByText('User Groups')).toBeInTheDocument();
    expect(await screen.findByText('Editors')).toBeInTheDocument();
  });

  it('shows groups after loading', async () => {
    render(<UserGroupsManager isAdmin currentUserId={1} />);
    expect(await screen.findByText('Everyone')).toBeInTheDocument();
    expect(screen.getByText('Editors')).toBeInTheDocument();
  });

  it('paginates root-level custom groups and keeps children with their parent', async () => {
    const rootGroups = Array.from({ length: 15 }, (_, i) => ({
      id: 100 + i, name: `Root Group ${i}`, slug: `root-${i}`, member_count: 0, is_system: false, parent_id: null,
    }));
    // Child of the very first root group — must always render alongside its parent.
    const child = { id: 200, name: 'Child Of Root 0', slug: 'child-0', member_count: 0, is_system: false, parent_id: 100 };

    mockApiFetch.mockResolvedValue({ user_groups: [ ...rootGroups, child ] });

    render(<UserGroupsManager isAdmin currentUserId={1} />);

    expect(await screen.findByText('Root Group 0')).toBeInTheDocument();
    expect(screen.getByText('Child Of Root 0')).toBeInTheDocument();
    expect(screen.getByText('Root Group 9')).toBeInTheDocument();
    expect(screen.queryByText('Root Group 10')).not.toBeInTheDocument();
    expect(screen.getByText('Page 1 of 2')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /Next/ }));

    expect(await screen.findByText('Root Group 10')).toBeInTheDocument();
    expect(screen.queryByText('Root Group 0')).not.toBeInTheDocument();
    expect(screen.queryByText('Child Of Root 0')).not.toBeInTheDocument();
    expect(screen.getByText('Page 2 of 2')).toBeInTheDocument();
  });

  describe('bulk select & delete', () => {
    const groupA = { id: 10, name: 'Group A', slug: 'group-a', member_count: 0, is_system: false, parent_id: null };
    const groupB = { id: 11, name: 'Group B', slug: 'group-b', member_count: 0, is_system: false, parent_id: null };
    const everyone = { id: 1, name: 'Everyone', slug: 'everyone', member_count: 5, is_system: true, parent_id: null };

    beforeEach(() => {
      mockApiFetch.mockResolvedValue({ user_groups: [ everyone, groupA, groupB ] });
    });

    it('shows a select-all checkbox and toggles selection state for root custom groups', async () => {
      render(<UserGroupsManager isAdmin currentUserId={1} />);
      expect(await screen.findByText('Group A')).toBeInTheDocument();

      const selectAll = screen.getByTestId('group-select-all');
      expect(selectAll).not.toBeChecked();

      fireEvent.click(selectAll.querySelector('input'));

      expect(screen.getByTestId('group-select-10').querySelector('input')).toBeChecked();
      expect(screen.getByTestId('group-select-11').querySelector('input')).toBeChecked();
      expect(screen.getByText('2 selected')).toBeInTheDocument();
    });

    it('deletes selected groups via bulk_delete and refreshes the list', async () => {
      mockApiFetch.mockResolvedValueOnce({ user_groups: [ everyone, groupA, groupB ] });
      render(<UserGroupsManager isAdmin currentUserId={1} />);
      expect(await screen.findByText('Group A')).toBeInTheDocument();

      fireEvent.click(screen.getByTestId('group-select-10').querySelector('input'));
      expect(screen.getByText('1 selected')).toBeInTheDocument();

      mockApiFetch.mockResolvedValueOnce({ success: true, deleted_ids: [ 10 ], message: '1 group(s) deleted.' });
      mockApiFetch.mockResolvedValueOnce({ user_groups: [ everyone, groupB ] });

      window.confirm = jest.fn(() => true);
      fireEvent.click(screen.getByTestId('group-bulk-delete-button'));

      await screen.findByText('Group B');
      expect(mockApiFetch).toHaveBeenCalledWith(
        '/admin/user_groups/bulk_delete.json',
        expect.objectContaining({ method: 'DELETE', body: JSON.stringify({ ids: [ 10 ] }) })
      );
      expect(mockNotify).toHaveBeenCalledWith('1 group(s) deleted.', 'success');
    });
  });
});
