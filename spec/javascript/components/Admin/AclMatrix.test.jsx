import React from 'react';
import { render, screen, waitFor, within, fireEvent } from '@testing-library/react';

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
}));

import AclMatrix from '../../../../app/javascript/components/Admin/AclMatrix';

describe('AclMatrix', () => {
  beforeEach(() => {
    mockNotify.mockReset();
    mockApiFetch.mockReset();
  });

  function mockInitialFetches() {
    mockApiFetch.mockImplementation((url) => {
      if (url === '/api/v1/folders.json') {
        return Promise.resolve({
          folders: [
            { id: 1, name: 'Root', path: '/Root' },
            { id: 2, name: 'Child', path: '/Root/Child' },
          ],
        });
      }
      if (url === '/admin/folders/1/folder_policies.json') {
        return Promise.resolve({
          explicit_policies: [
            { group_id: 99, matrix: { read: true, create: true } },
          ],
          inherited_policies: [],
        });
      }
      if (url === '/admin/folders/2/folder_policies.json') {
        return Promise.resolve({
          explicit_policies: [],
          inherited_policies: [
            { group_id: 99, matrix: { read: true }, source_folder: '/Root' },
          ],
        });
      }
      return Promise.resolve({ success: true });
    });
  }

  it('renders without crashing and shows a loading state first', async () => {
    mockInitialFetches();

    render(<AclMatrix groupId={99} isAdmin />);

    expect(screen.getByRole('progressbar')).toBeInTheDocument();
    expect(await screen.findByText('/Root')).toBeInTheDocument();
  });

  it('shows the ACL table when data loads', async () => {
    mockInitialFetches();

    render(<AclMatrix groupId={99} isAdmin />);

    expect(await screen.findByText('aclMatrix.path')).toBeInTheDocument();
    expect(screen.getByText('/Root')).toBeInTheDocument();
    expect(screen.getByText('/Root/Child')).toBeInTheDocument();
    expect(screen.getByText('aclMatrix.inherited')).toBeInTheDocument();
  });

  it('updates a permission toggle and saves it', async () => {
    mockApiFetch.mockImplementation((url, options) => {
      if (options?.method === 'POST') return Promise.resolve({ success: true });
      if (url === '/api/v1/folders.json') {
        return Promise.resolve({ folders: [{ id: 1, name: 'Root', path: '/Root' }] });
      }
      if (url === '/admin/folders/1/folder_policies.json') {
        return Promise.resolve({
          explicit_policies: [{ group_id: 99, matrix: { read: true } }],
          inherited_policies: [],
        });
      }
      return Promise.resolve({});
    });

    render(<AclMatrix groupId={99} isAdmin />);

    const row = (await screen.findByText('/Root')).closest('tr');
    const checkboxes = within(row).getAllByRole('checkbox');
    fireEvent.click(checkboxes[1]);
    fireEvent.click(within(row).getAllByRole('button')[0]);

    await waitFor(() => {
      expect(mockApiFetch).toHaveBeenCalledWith(
        '/admin/folders/1/folder_policies.json',
        expect.objectContaining({ method: 'POST' })
      );
    });

    const saveCall = mockApiFetch.mock.calls.find(([url, opts]) => url === '/admin/folders/1/folder_policies.json' && opts?.method === 'POST');
    expect(JSON.parse(saveCall[1].body)).toEqual(expect.objectContaining({
      group_id: 99,
      policy: expect.objectContaining({ read_access: true, modify_access: true }),
    }));
  });

  it('shows only root folders by default and reveals children on expand', async () => {
    mockApiFetch.mockImplementation((url) => {
      if (url === '/api/v1/folders.json') {
        return Promise.resolve({
          folders: [
            { id: 1, name: 'Root', path: '/Root', parent_id: null },
            { id: 2, name: 'Child', path: '/Root/Child', parent_id: 1 },
          ],
        });
      }
      if (url === '/admin/folders/1/folder_policies.json') {
        return Promise.resolve({
          explicit_policies: [{ group_id: 99, matrix: { read: true } }],
          inherited_policies: [],
        });
      }
      return Promise.resolve({ explicit_policies: [], inherited_policies: [] });
    });

    render(<AclMatrix groupId={99} isAdmin />);

    expect(await screen.findByText('/Root')).toBeInTheDocument();
    expect(screen.queryByText('/Root/Child')).not.toBeInTheDocument();

    fireEvent.click(screen.getByTestId('acl-toggle-1'));

    expect(await screen.findByText('/Root/Child')).toBeInTheDocument();
  });

  it('cascades a toggled permission onto expanded descendant rows', async () => {
    mockApiFetch.mockImplementation((url) => {
      if (url === '/api/v1/folders.json') {
        return Promise.resolve({
          folders: [
            { id: 1, name: 'Root', path: '/Root', parent_id: null },
            { id: 2, name: 'Child', path: '/Root/Child', parent_id: 1 },
          ],
        });
      }
      if (url === '/admin/folders/1/folder_policies.json') {
        return Promise.resolve({
          explicit_policies: [{ group_id: 99, matrix: { read: true } }],
          inherited_policies: [],
        });
      }
      return Promise.resolve({ explicit_policies: [], inherited_policies: [] });
    });

    render(<AclMatrix groupId={99} isAdmin />);

    await screen.findByText('/Root');
    fireEvent.click(screen.getByTestId('acl-toggle-1'));
    await screen.findByText('/Root/Child');

    const rootRow = screen.getByTestId('acl-row-1');
    const childRow = screen.getByTestId('acl-row-2');

    // Toggle "modify" (2nd checkbox) on the root folder.
    fireEvent.click(within(rootRow).getAllByRole('checkbox')[1]);

    // The previously-unset child row should now reflect the cascaded value too.
    expect(within(childRow).getAllByRole('checkbox')[1]).toBeChecked();

    // The user can still override the child individually afterwards.
    fireEvent.click(within(childRow).getAllByRole('checkbox')[1]);
    expect(within(childRow).getAllByRole('checkbox')[1]).not.toBeChecked();
  });

  it('sends cascade: true when the subfolder save switch is enabled', async () => {
    mockApiFetch.mockImplementation((url, options) => {
      if (options?.method === 'POST') return Promise.resolve({ success: true });
      if (url === '/api/v1/folders.json') {
        return Promise.resolve({
          folders: [
            { id: 1, name: 'Root', path: '/Root', parent_id: null },
            { id: 2, name: 'Child', path: '/Root/Child', parent_id: 1 },
          ],
        });
      }
      if (url === '/admin/folders/1/folder_policies.json') {
        return Promise.resolve({
          explicit_policies: [{ group_id: 99, matrix: { read: true } }],
          inherited_policies: [],
        });
      }
      return Promise.resolve({ explicit_policies: [], inherited_policies: [] });
    });

    render(<AclMatrix groupId={99} isAdmin />);

    await screen.findByText('/Root');

    fireEvent.click(screen.getByTestId('acl-cascade-switch-1'));
    fireEvent.click(screen.getByTestId('acl-save-1'));

    await waitFor(() => {
      const saveCall = mockApiFetch.mock.calls.find(
        ([url, opts]) => url === '/admin/folders/1/folder_policies.json' && opts?.method === 'POST'
      );
      expect(saveCall).toBeTruthy();
      expect(JSON.parse(saveCall[1].body)).toEqual(expect.objectContaining({ cascade: true }));
    });
  });
});
