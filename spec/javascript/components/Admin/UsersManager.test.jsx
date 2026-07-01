import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';

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

jest.mock('../../../../app/javascript/components/Admin/UserDrawer', () => ({ open, user }) => (
  open ? <div>UserDrawer:{user?.email || 'new-user'}</div> : null
));

jest.mock('../../../../app/javascript/components/Admin/GroupAssignmentModal', () => ({ open }) => (
  open ? <div>GroupAssignmentModal Open</div> : null
));

jest.mock('@mui/x-data-grid', () => {
  const React = require('react');
  const DataGrid = ({ rows, columns, loading, onRowClick, slots }) => (
    <div data-testid="users-grid">
      {slots?.toolbar ? React.createElement(slots.toolbar) : null}
      {loading ? <div>Loading...</div> : null}
      <table>
        <tbody>
          {rows.map((row) => (
            <tr key={row.id} onClick={() => onRowClick?.({ row })}>
              {columns.map((col) => {
                const value = row[col.field];
                return <td key={col.field}>{col.renderCell ? col.renderCell({ row, value }) : value}</td>;
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
  const Button = ({ children }) => <button type="button">{children}</button>;
  return {
    DataGrid,
    GridToolbarContainer: ({ children }) => <div>{children}</div>,
    GridToolbarColumnsButton: Button,
    GridToolbarFilterButton: Button,
    GridToolbarDensitySelector: Button,
    GridToolbarExport: Button,
  };
});

import UsersManager from '../../../../app/javascript/components/Admin/UsersManager';

describe('UsersManager', () => {
  beforeEach(() => {
    mockNotify.mockReset();
    mockApiFetch.mockReset();
    mockApiFetch.mockImplementation((url) => {
      if (url.startsWith('/admin/users.json')) {
        return Promise.resolve({
          users: [{
            id: 1,
            display_name: 'Alice Admin',
            email: 'alice@example.com',
            department: 'Ops',
            role: 'Lead',
            groups: ['Editors'],
            active: true,
          }],
          total_count: 1,
        });
      }
      if (url === '/admin/user_groups.json') {
        return Promise.resolve({ user_groups: [{ id: 7, name: 'Editors' }] });
      }
      return Promise.resolve({ success: true });
    });
  });

  it('renders without crashing', async () => {
    render(<UsersManager isAdmin isSuperAdmin />);
    expect(screen.getByText('System Users')).toBeInTheDocument();
    expect(await screen.findByText('Alice Admin')).toBeInTheDocument();
  });

  it('shows the users table after fetch', async () => {
    render(<UsersManager isAdmin isSuperAdmin />);
    expect(await screen.findByText('alice@example.com')).toBeInTheDocument();
    expect(screen.getByTestId('users-grid')).toBeInTheDocument();
  });

  it('opens the create user drawer from the button', async () => {
    render(<UsersManager isAdmin isSuperAdmin />);
    await waitFor(() => expect(mockApiFetch).toHaveBeenCalled());

    fireEvent.click(screen.getByText('Invite Local User'));
    expect(screen.getByText('UserDrawer:new-user')).toBeInTheDocument();
  });
});
