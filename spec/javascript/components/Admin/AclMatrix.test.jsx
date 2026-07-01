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

    expect(await screen.findByText('Path')).toBeInTheDocument();
    expect(screen.getByText('/Root')).toBeInTheDocument();
    expect(screen.getByText('/Root/Child')).toBeInTheDocument();
    expect(screen.getByText('inherited')).toBeInTheDocument();
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
});
