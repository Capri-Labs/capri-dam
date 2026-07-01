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
  SYSTEM_SLUGS: { EVERYONE: 'everyone', ADMINS: 'administrators', SUPER_ADMINS: 'super-administrators' },
  isSystemGroup: (group) => group.is_system,
  isSelfPromotion: () => false,
  groupPermissions: () => ({ canDelete: true, canAddMembers: true, canRemoveMembers: true }),
}));

jest.mock('../../../../app/javascript/components/Admin/AclMatrix', () => () => <div>ACL Matrix Mock</div>);
jest.mock('../../../../app/javascript/components/Admin/UserSearch', () => () => <div>User Search Mock</div>);
jest.mock('../../../../app/javascript/components/Admin/GroupSearch', () => () => <div>Group Search Mock</div>);

import GroupOverlay from '../../../../app/javascript/components/Admin/GroupOverlay';

describe('GroupOverlay', () => {
  const group = {
    id: 4,
    name: 'Editors',
    description: 'Editorial team',
    slug: 'editors',
    member_count: 3,
  };

  it('renders without crashing', () => {
    render(
      <GroupOverlay
        open
        group={group}
        onClose={jest.fn()}
        onGroupUpdated={jest.fn()}
        allGroups={[]}
        isAdmin
        isSuperAdmin
      />
    );

    expect(screen.getByText('Editors')).toBeInTheDocument();
  });

  it('shows group info', () => {
    render(
      <GroupOverlay
        open
        group={group}
        onClose={jest.fn()}
        onGroupUpdated={jest.fn()}
        allGroups={[]}
        isAdmin
        isSuperAdmin
      />
    );

    expect(screen.getByText(/Editorial team/)).toBeInTheDocument();
    expect(screen.getByDisplayValue('Editors')).toBeInTheDocument();
    expect(screen.getByDisplayValue('Editorial team')).toBeInTheDocument();
  });

  it('closes from the close button', () => {
    const onClose = jest.fn();
    render(
      <GroupOverlay
        open
        group={group}
        onClose={onClose}
        onGroupUpdated={jest.fn()}
        allGroups={[]}
        isAdmin
        isSuperAdmin
      />
    );

    fireEvent.click(screen.getAllByRole('button').slice(-1)[0]);
    expect(onClose).toHaveBeenCalled();
  });
});
