import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';

const mockNotify = jest.fn();
const mockApiFetch = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

jest.mock('../../../../app/javascript/utils/adminUtils', () => ({
  apiFetch: (...args) => mockApiFetch(...args),
  formatDate: () => 'Jan 1, 2024',
  SYSTEM_SLUGS: { EVERYONE: 'everyone', ADMINS: 'administrators', SUPER_ADMINS: 'super-administrators' },
  groupPermissions: () => ({ canRemoveMembers: true, canAddMembers: true, canAssignUser: true }),
}));

jest.mock('../../../../app/javascript/components/Admin/AclMatrix', () => () => <div>ACL Matrix Mock</div>);
jest.mock('../../../../app/javascript/components/Admin/UserSearch', () => () => <div>User Search Mock</div>);
jest.mock('../../../../app/javascript/components/Admin/GroupSearch', () => () => <div>Group Search Mock</div>);

import UserDrawer from '../../../../app/javascript/components/Admin/UserDrawer';

const user = {
  id: 9,
  display_name: 'Alice Admin',
  email: 'alice@example.com',
  first_name: 'Alice',
  last_name: 'Admin',
  active: true,
  admin: true,
  group_ids: [1],
  created_at: '2024-01-01T00:00:00Z',
};

const editForm = {
  first_name: 'Alice',
  last_name: 'Admin',
  email: 'alice@example.com',
  department: 'Ops',
  role: 'Manager',
  admin: true,
};

describe('UserDrawer', () => {
  it('renders when open=true', () => {
    render(
      <UserDrawer
        open
        user={user}
        editForm={editForm}
        setEditForm={jest.fn()}
        onClose={jest.fn()}
        onSave={jest.fn()}
        onToggleStatus={jest.fn()}
        allGroups={[]}
        isAdmin
        isSuperAdmin
      />
    );

    expect(screen.getByText('Alice Admin')).toBeInTheDocument();
    expect(screen.getByText('Properties')).toBeInTheDocument();
  });

  it('shows user fields', () => {
    render(
      <UserDrawer
        open
        user={user}
        editForm={editForm}
        setEditForm={jest.fn()}
        onClose={jest.fn()}
        onSave={jest.fn()}
        onToggleStatus={jest.fn()}
        allGroups={[]}
        isAdmin
        isSuperAdmin
      />
    );

    expect(screen.getByDisplayValue('Alice')).toBeInTheDocument();
    expect(screen.getByDisplayValue('Admin')).toBeInTheDocument();
    expect(screen.getByDisplayValue('alice@example.com')).toBeInTheDocument();
  });

  it('calls onClose when the close button is clicked', () => {
    const onClose = jest.fn();
    render(
      <UserDrawer
        open
        user={user}
        editForm={editForm}
        setEditForm={jest.fn()}
        onClose={onClose}
        onSave={jest.fn()}
        onToggleStatus={jest.fn()}
        allGroups={[]}
        isAdmin
        isSuperAdmin
      />
    );

    fireEvent.click(screen.getAllByRole('button')[0]);
    expect(onClose).toHaveBeenCalled();
  });
});
