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
});
