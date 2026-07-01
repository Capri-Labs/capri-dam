import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import Settings from '../../../app/javascript/components/Settings';

jest.mock('../../../app/javascript/components/Admin/SystemStatus/index.jsx', () => () => <div>SystemStatus</div>);
jest.mock('../../../app/javascript/components/Sidebar.jsx', () => () => <div>Sidebar</div>);
jest.mock('../../../app/javascript/utils/globalutils.js', () => ({ navigateTo: jest.fn() }));

describe('Settings', () => {
  const props = {
    userIsAdmin: 'true',
    systemApps: JSON.stringify([{ id: 1, name: 'Marketing API', uid: 'abcdef123456' }]),
    allConfigs: JSON.stringify({ local: {}, aws: { access_key: 'key', secret_key: 'secret', region: 'us-east-1', bucket: 'bucket' } }),
    activeProvider: 'local',
  };

  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === '[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
    window.confirm = jest.fn(() => true);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('renders the settings admin sections and service accounts', () => {
    render(<Settings {...props} />);

    expect(screen.getByText('System Administration')).toBeInTheDocument();
    expect(screen.getByText('System Service Accounts')).toBeInTheDocument();
    expect(screen.getByText('Marketing API')).toBeInTheDocument();
    expect(screen.getByText('Storage Backend Configuration')).toBeInTheDocument();
  });

  it('shows provider-specific fields for aws', async () => {
    render(<Settings {...props} activeProvider="aws" />);

    expect(await screen.findByText('Access Key ID')).toBeInTheDocument();
    expect(screen.getByText('Bucket Name')).toBeInTheDocument();
  });

  it('toggles advanced options and handles connection/save actions', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValueOnce({ ok: true, json: async () => ({ success: true, message: 'Connected successfully' }) })
      .mockResolvedValueOnce({ ok: true, json: async () => ({ message: 'Saved successfully' }) });

    render(<Settings {...props} activeProvider="aws" />);

    fireEvent.click(screen.getByRole('button', { name: /Advanced Options/i }));
    expect(await screen.findByLabelText('Presigned URL Expiry (seconds)')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Test Connection' }));
    expect(await screen.findByText('Connected successfully')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /Save & Activate/i }));
    expect(await screen.findByText('Saved successfully')).toBeInTheDocument();
  });
});
