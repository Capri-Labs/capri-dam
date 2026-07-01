import React from 'react';
import { render, screen, fireEvent, within } from '@testing-library/react';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/utils/adminUtils', () => ({
  SYSTEM_SLUGS: { EVERYONE: 'everyone', ADMINS: 'administrators', SUPER_ADMINS: 'super-administrators' },
  isSystemGroup: (group) => group.is_system,
  groupPermissions: () => ({ canAssignUser: true }),
}));

import GroupAssignmentModal from '../../../../app/javascript/components/Admin/GroupAssignmentModal';

describe('GroupAssignmentModal', () => {
  const user = { id: 7, email: 'alice@example.com', group_ids: [] };
  const allGroups = [
    { id: 1, name: 'Editors', slug: 'editors', parent_id: null },
    { id: 2, name: 'Sub Editors', slug: 'sub-editors', parent_id: 1 },
  ];

  it('renders when open', () => {
    render(
      <GroupAssignmentModal
        open
        user={user}
        allGroups={allGroups}
        onClose={jest.fn()}
        onSave={jest.fn()}
        isAdmin
      />
    );

    expect(screen.getByText('Group Hierarchy & Access')).toBeInTheDocument();
  });

  it('shows available groups', () => {
    render(
      <GroupAssignmentModal
        open
        user={user}
        allGroups={allGroups}
        onClose={jest.fn()}
        onSave={jest.fn()}
        isAdmin
      />
    );

    expect(screen.getByText('Editors')).toBeInTheDocument();
    expect(screen.getByText('Sub Editors')).toBeInTheDocument();
  });

  it('calls assign on save', () => {
    const onSave = jest.fn();
    render(
      <GroupAssignmentModal
        open
        user={user}
        allGroups={allGroups}
        onClose={jest.fn()}
        onSave={onSave}
        isAdmin
      />
    );

    const item = screen.getByText('Editors').closest('li');
    fireEvent.click(within(item).getByRole('checkbox'));
    fireEvent.click(screen.getByText('Save Group Assignments'));

    expect(onSave).toHaveBeenCalledWith(7, expect.arrayContaining([1, 2]));
  });
});
