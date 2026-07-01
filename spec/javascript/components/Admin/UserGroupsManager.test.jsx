import React from 'react';
import { render, screen } from '@testing-library/react';

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
});
