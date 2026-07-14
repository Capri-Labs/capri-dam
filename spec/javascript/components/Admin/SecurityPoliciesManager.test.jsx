import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';

const mockNotify = jest.fn();
const mockApiFetch = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key, opts) => (opts?.name ? key.replace('{{name}}', opts.name) : key) }),
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

jest.mock('../../../../app/javascript/utils/adminUtils', () => ({
  apiFetch: (...args) => mockApiFetch(...args),
  isSystemGroup: (g) => g.is_system,
  SYSTEM_SLUGS: { EVERYONE: 'everyone', ADMINS: 'administrators', SUPER_ADMINS: 'super-administrators' },
}));

jest.mock('../../../../app/javascript/components/Admin/AclMatrix', () => (props) => (
  <div data-testid="acl-matrix-mock">ACL Matrix for group {props.groupId} (readOnly={String(props.readOnly)})</div>
));

import SecurityPoliciesManager from '../../../../app/javascript/components/Admin/SecurityPoliciesManager';

const GROUPS = [
  { id: 1, name: 'Everyone', slug: 'everyone', is_system: true, member_count: 42 },
  { id: 2, name: 'Administrators', slug: 'administrators', is_system: true, member_count: 3 },
  { id: 3, name: 'Marketing Editors', slug: null, is_system: false, member_count: 7 },
  { id: 4, name: 'Brand Reviewers', slug: null, is_system: false, member_count: 2 },
];

describe('SecurityPoliciesManager', () => {
  beforeEach(() => {
    mockNotify.mockReset();
    mockApiFetch.mockReset();
    mockApiFetch.mockResolvedValue({ user_groups: GROUPS });
  });

  it('shows a loading state, then the group list split into System/Custom sections', async () => {
    render(<SecurityPoliciesManager isAdmin />);

    expect(screen.getByRole('progressbar')).toBeInTheDocument();

    expect(await screen.findByText('Marketing Editors')).toBeInTheDocument();
    expect(screen.getByText('Everyone')).toBeInTheDocument();
    expect(screen.getByText('Administrators')).toBeInTheDocument();
    expect(screen.getByText('Brand Reviewers')).toBeInTheDocument();
    expect(screen.getByText('securityPolicies.systemGroups')).toBeInTheDocument();
    expect(screen.getByText('securityPolicies.customGroups')).toBeInTheDocument();

    expect(mockApiFetch).toHaveBeenCalledWith('/admin/user_groups.json');
  });

  it('auto-selects the first group and renders its ACL matrix', async () => {
    render(<SecurityPoliciesManager isAdmin />);

    expect(await screen.findByTestId('acl-matrix-mock')).toHaveTextContent('ACL Matrix for group 1');
  });

  it('switches the matrix when a different group is clicked', async () => {
    render(<SecurityPoliciesManager isAdmin />);

    await screen.findByText('Marketing Editors');
    fireEvent.click(screen.getByText('Marketing Editors'));

    expect(await screen.findByTestId('acl-matrix-mock')).toHaveTextContent('ACL Matrix for group 3');
  });

  it('filters the group list via the search box', async () => {
    render(<SecurityPoliciesManager isAdmin />);

    await screen.findByText('Marketing Editors');
    fireEvent.change(screen.getByPlaceholderText('securityPolicies.searchPlaceholder'), { target: { value: 'brand' } });

    expect(await screen.findByText('Brand Reviewers')).toBeInTheDocument();
    expect(screen.queryByText('Marketing Editors')).not.toBeInTheDocument();
    expect(screen.queryByText('Everyone')).not.toBeInTheDocument();
  });

  it('shows a "no groups match" message when the search has no results', async () => {
    render(<SecurityPoliciesManager isAdmin />);

    await screen.findByText('Marketing Editors');
    fireEvent.change(screen.getByPlaceholderText('securityPolicies.searchPlaceholder'), { target: { value: 'zzz-no-match' } });

    expect(await screen.findByText('securityPolicies.noGroups')).toBeInTheDocument();
  });

  it('marks the matrix read-only for non-admins', async () => {
    render(<SecurityPoliciesManager isAdmin={false} />);

    expect(await screen.findByTestId('acl-matrix-mock')).toHaveTextContent('readOnly=true');
  });

  it('marks the "Everyone" system group matrix read-only even for admins', async () => {
    render(<SecurityPoliciesManager isAdmin />);

    await screen.findByText('Marketing Editors');
    fireEvent.click(screen.getByText('Everyone'));

    expect(await screen.findByTestId('acl-matrix-mock')).toHaveTextContent('readOnly=true');
  });

  it('notifies on load failure', async () => {
    mockApiFetch.mockRejectedValue(new Error('network down'));

    render(<SecurityPoliciesManager isAdmin />);

    await waitFor(() => expect(mockNotify).toHaveBeenCalledWith('securityPolicies.notifications.loadFailed', 'error'));
  });
});
