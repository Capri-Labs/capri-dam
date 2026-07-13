import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import OriginStorageTab from '../../../../../app/javascript/components/Admin/SystemStatus/OriginStorageTab';

describe('OriginStorageTab', () => {
  const props = {
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

  it('renders the storage backend configuration section', () => {
    render(<OriginStorageTab {...props} />);

    expect(screen.getByText('Storage Backend Configuration')).toBeInTheDocument();
  });

  it('shows provider-specific fields for aws', async () => {
    render(<OriginStorageTab {...props} activeProvider="aws" />);

    expect(await screen.findByText('Access Key ID')).toBeInTheDocument();
    expect(screen.getByText('Bucket Name')).toBeInTheDocument();
  });

  it('toggles advanced options and handles connection/save actions', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValueOnce({ ok: true, json: async () => ({ success: true, message: 'Connected successfully' }) })
      .mockResolvedValueOnce({ ok: true, json: async () => ({ message: 'Saved successfully' }) });

    render(<OriginStorageTab {...props} activeProvider="aws" />);

    fireEvent.click(screen.getByRole('button', { name: /Advanced Options/i }));
    expect(await screen.findByLabelText('Presigned URL Expiry (seconds)')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Test Connection' }));
    expect(await screen.findByText('Connected successfully')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /Save & Activate/i }));
    expect(await screen.findByText('Saved successfully')).toBeInTheDocument();
  });
});
