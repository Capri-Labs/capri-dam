import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import SystemAccountNew from '../../../../app/javascript/components/system_accounts/SystemAccountNew';
import SystemAccountShow from '../../../../app/javascript/components/system_accounts/SystemAccountShow';

jest.mock('../../../../app/javascript/components/Sidebar.jsx', () => () => <div>Sidebar</div>);

describe('System account components', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === '[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
    navigator.clipboard.writeText = jest.fn();
    window.confirm = jest.fn(() => true);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('renders SystemAccountNew form fields and enables submit when named', () => {
    render(<SystemAccountNew />);

    expect(screen.getByText('New Service Account')).toBeInTheDocument();
    const field = screen.getByLabelText(/Application Name/i);
    const submit = screen.getByRole('button', { name: 'Generate Credentials' });

    expect(submit).toBeDisabled();
    fireEvent.change(field, { target: { value: 'Marketing API' } });
    expect(submit).not.toBeDisabled();
  });

  it('shows SystemAccountShow details', () => {
    render(<SystemAccountShow appJson={JSON.stringify({ id: 1, name: 'Marketing API', uid: 'uid-123', secret: 'secret-456' })} />);

    expect(screen.getByText('Application Credentials')).toBeInTheDocument();
    expect(screen.getByDisplayValue('uid-123')).toBeInTheDocument();
    expect(screen.getByDisplayValue('secret-456')).toBeInTheDocument();
    expect(screen.getByText('Security Warning')).toBeInTheDocument();
  });

  it('renders the revoke action in SystemAccountShow', () => {
    render(<SystemAccountShow appJson={JSON.stringify({ id: 1, name: 'Marketing API', uid: 'uid-123', secret: 'secret-456' })} />);
    expect(screen.getByRole('button', { name: 'Revoke Credentials' })).toBeInTheDocument();
  });
});
