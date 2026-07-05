import React from 'react';
import { render, screen, waitFor, fireEvent, act } from '@testing-library/react';

const mockNotify = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

jest.mock('../../../../app/javascript/components/Admin/SystemStatus/FeatureFlagsTab', () => () => <div>Feature Flags Tab</div>);

import AiGatewayTab from '../../../../app/javascript/components/Admin/SystemStatus/AiGatewayTab';
import ObservabilityTab from '../../../../app/javascript/components/Admin/SystemStatus/ObservabilityTab';
import OperationalLoggingTab from '../../../../app/javascript/components/Admin/SystemStatus/OperationalLoggingTab';
import SmtpSettingsTab from '../../../../app/javascript/components/Admin/SystemStatus/SmtpSettingsTab';
import StorageOperationsTab from '../../../../app/javascript/components/Admin/SystemStatus/StorageOperationsTab';
import SystemStatus from '../../../../app/javascript/components/Admin/SystemStatus';

describe('SystemStatus tabs', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    const _csrfMeta = document.head.querySelector('meta[name="csrf-token"]') || (() => { const m = document.createElement('meta'); m.name = 'csrf-token'; document.head.appendChild(m); return m; })(); _csrfMeta.content = 'token';
    window.confirm = jest.fn(() => true);
    global.fetch = jest.fn((url, options = {}) => {
      if (url === '/admin/system_status.json') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({
          app_server: { status: 'healthy', ruby_version: '4.0.3', rails_version: '8.1' },
          database: { status: 'healthy', latency_ms: 12, pool_size: 5, active_connections: 2 },
          cache_queue: { status: 'healthy', active_workers: 3, queue_depth: 1, latency_ms: 9 },
          storage_backend: { status: 'healthy', latency_ms: 20, provider: 'S3' },
        }) });
      }
      if (url === '/admin/system_status/restart_server') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ message: 'Restart queued' }) });
      }
      if (url === '/admin/system_configurations/logging' && !options.method) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true, current_level: 'INFO', ttl_active: true, minutes_remaining: 15 }) });
      }
      if (url === '/admin/system_configurations/logging' && options.method === 'POST') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true, message: 'Updated' }) });
      }
      if (url === '/admin/system_status/update_smtp') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true, message: 'SMTP saved' }) });
      }
      if (url === '/admin/system_status/test_connection') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
      }
      if (url === '/admin/system_status/test_email') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true, message: 'Test sent' }) });
      }
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
    });
  });

  afterEach(async () => {
    await act(async () => { jest.runOnlyPendingTimers(); });
    jest.useRealTimers();
  });

  it('renders AiGatewayTab', async () => {
    render(<AiGatewayTab />);
    act(() => jest.advanceTimersByTime(500));
    expect(await screen.findByText('AI & LLM Gateway Governance')).toBeInTheDocument();
    fireEvent.click(screen.getByText('Save & Sync Gateway'));
    act(() => jest.advanceTimersByTime(800));
    await waitFor(() => expect(mockNotify).toHaveBeenCalled());
  });

  it('renders ObservabilityTab with health cards', async () => {
    render(<ObservabilityTab />);
    expect(await screen.findByText('Puma Rack')).toBeInTheDocument();
    expect(screen.getByText('PostgreSQL')).toBeInTheDocument();
  });

  it('renders OperationalLoggingTab and applies config', async () => {
    await act(async () => { render(<OperationalLoggingTab />); });
    expect(await screen.findByText('Adjust Log Verbosity')).toBeInTheDocument();
    fireEvent.click(screen.getByText('Apply Configuration'));
    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(
      '/admin/system_configurations/logging',
      expect.objectContaining({ method: 'POST' })
    ));
  });

  it('renders SmtpSettingsTab with fields', async () => {
    await act(async () => { render(<SmtpSettingsTab incomingConfigs={{ address: 'smtp.example.com', sender_address: 'noreply@example.com' }} />); });
    expect(screen.getByText('SMTP Infrastructure Setup')).toBeInTheDocument();
    expect(screen.getByDisplayValue('smtp.example.com')).toBeInTheDocument();
    expect(screen.getByDisplayValue('noreply@example.com')).toBeInTheDocument();
  });

  it('runs a pre-flight SMTP connection test without sending an email', async () => {
    await act(async () => { render(<SmtpSettingsTab incomingConfigs={{ address: 'smtp.example.com', sender_address: 'noreply@example.com' }} />); });

    fireEvent.click(screen.getByText('smtpSettings.testConnection'));

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(
      '/admin/system_status/test_connection',
      expect.objectContaining({ method: 'POST' })
    ));
    expect(await screen.findByText('smtpSettings.connectionVerified')).toBeInTheDocument();
  });

  it('surfaces a localized error code when the SMTP connection test fails', async () => {
    global.fetch = jest.fn((url) => {
      if (url === '/admin/system_status/test_connection') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: false, error_code: 'CONNECTION_TIMEOUT', error: 'timed out' }) });
      }
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
    });

    await act(async () => { render(<SmtpSettingsTab incomingConfigs={{ address: 'smtp.example.com', sender_address: 'noreply@example.com' }} />); });

    fireEvent.click(screen.getByText('smtpSettings.testConnection'));

    expect(await screen.findByText('smtpSettings.errorCodes.CONNECTION_TIMEOUT')).toBeInTheDocument();
  });

  it('renders StorageOperationsTab', async () => {
    await act(async () => { render(<StorageOperationsTab />); });
    await act(async () => { jest.advanceTimersByTime(600); });
    expect(await screen.findByText('Infrastructure Routing')).toBeInTheDocument();
    expect(screen.getByText('Save CDN Settings')).toBeInTheDocument();
  });

  it('renders SystemStatus main and switches tabs', async () => {
    await act(async () => { render(<SystemStatus incomingConfigs={{ address: 'smtp.example.com' }} />); });
    expect(screen.getByText('System Operations')).toBeInTheDocument();
    expect(await screen.findByText('Puma Rack')).toBeInTheDocument();
    fireEvent.click(screen.getByText('SMTP & Email Settings'));
    expect(await screen.findByText('SMTP Infrastructure Setup')).toBeInTheDocument();
  });
});
