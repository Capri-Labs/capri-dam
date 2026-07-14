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
jest.mock('../../../../app/javascript/utils/globalutils.js', () => ({ navigateTo: jest.fn() }));

import AiGatewayTab from '../../../../app/javascript/components/Admin/SystemStatus/AiGatewayTab';
import ObservabilityTab from '../../../../app/javascript/components/Admin/SystemStatus/ObservabilityTab';
import OperationalLoggingTab from '../../../../app/javascript/components/Admin/SystemStatus/OperationalLoggingTab';
import SmtpSettingsTab from '../../../../app/javascript/components/Admin/SystemStatus/SmtpSettingsTab';
import StorageOperationsTab from '../../../../app/javascript/components/Admin/SystemStatus/StorageOperationsTab';
import AuditLogTab from '../../../../app/javascript/components/Admin/SystemStatus/AuditLogTab';
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
      if (url.startsWith('/admin/audit_logs')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({
          audit_logs: [
            {
              id: 1,
              action: 'update',
              auditable_type: 'Folder',
              auditable_id: 7,
              changes_data: { name: [ 'old', 'new' ] },
              impersonated: false,
              ip_address: '127.0.0.1',
              created_at: '2026-01-15T10:00:00Z',
              user: { id: 1, email: 'admin@example.com', name: 'Admin' },
              true_user: null,
            },
          ],
          pagination: { page: 1, per_page: 25, total: 1, total_pages: 1 },
          filter_options: { actions: [ 'create', 'update' ], auditable_types: [ 'Folder', 'Asset' ] },
        }) });
      }
      if (url === '/api/v1/cdn_configurations' && (!options.method || options.method === 'GET')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({
          fastly: { is_active: true, settings: { service_id: 'svc-123', api_key: '••••••••abcd', image_optimizer_formats: [ 'webp' ] } },
          cloudflare: { is_active: false, settings: {} },
          akamai: { is_active: false, settings: {} },
        }) });
      }
      if (url === '/api/v1/cdn_configurations' && options.method === 'PUT') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true, message: 'Fastly configuration updated.' }) });
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
    expect(await screen.findByText('operationalLogging.adjustVerbosity')).toBeInTheDocument();
    fireEvent.click(screen.getByText('operationalLogging.applyConfiguration'));
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

  it('renders the Origin Storage sub-tab with storage backend configuration', async () => {
    const storageProps = {
      allConfigs: JSON.stringify({ local: {} }),
      activeProvider: 'local',
    };
    await act(async () => { render(<StorageOperationsTab {...storageProps} />); });
    await act(async () => { jest.advanceTimersByTime(600); });

    fireEvent.click(screen.getByText('Origin Storage'));

    expect(await screen.findByText('Storage Backend Configuration')).toBeInTheDocument();
  });

  it('loads the real CDN configuration from the API and pre-checks the saved image optimizer formats', async () => {
    await act(async () => { render(<StorageOperationsTab />); });

    expect(await screen.findByDisplayValue('svc-123')).toBeInTheDocument();
    expect(screen.getByLabelText('webp')).toBeChecked();
    expect(screen.getByLabelText('avif')).not.toBeChecked();
    expect(global.fetch).toHaveBeenCalledWith('/api/v1/cdn_configurations');
  });

  it('toggles the AVIF checkbox and saves the updated format list via a real PUT request', async () => {
    await act(async () => { render(<StorageOperationsTab />); });
    await screen.findByDisplayValue('svc-123');

    fireEvent.click(screen.getByLabelText('avif'));
    expect(screen.getByLabelText('avif')).toBeChecked();

    fireEvent.click(screen.getByText('Save CDN Settings'));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/cdn_configurations', expect.objectContaining({
        method: 'PUT',
        headers: expect.objectContaining({ 'X-CSRF-Token': 'token' }),
      }));
    });

    const putCall = global.fetch.mock.calls.find(([ url, opts ]) => url === '/api/v1/cdn_configurations' && opts?.method === 'PUT');
    const body = JSON.parse(putCall[1].body);
    expect(body.provider).toBe('fastly');
    expect(body.settings.image_optimizer_formats).toEqual([ 'webp', 'avif' ]);

    expect(await screen.findByText('Fastly configuration updated.')).toBeInTheDocument();
  });

  it('surfaces a validation error when the API rejects an unsupported format', async () => {
    global.fetch = jest.fn((url, options = {}) => {
      if (url === '/api/v1/cdn_configurations' && (!options.method || options.method === 'GET')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({
          fastly: { is_active: true, settings: { service_id: 'svc-123', image_optimizer_formats: [ 'webp' ] } },
          cloudflare: { is_active: false, settings: {} },
          akamai: { is_active: false, settings: {} },
        }) });
      }
      if (url === '/api/v1/cdn_configurations' && options.method === 'PUT') {
        return Promise.resolve({ ok: false, status: 422, json: () => Promise.resolve({ errors: [ 'Unsupported image optimizer format(s): jxl.' ] }) });
      }
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
    });

    await act(async () => { render(<StorageOperationsTab />); });
    await screen.findByDisplayValue('svc-123');

    fireEvent.click(screen.getByText('Save CDN Settings'));

    expect(await screen.findByText(/Unsupported image optimizer format/)).toBeInTheDocument();
  });

  it('renders AuditLogTab with fetched entries', async () => {
    await act(async () => { render(<AuditLogTab />); });

    expect(await screen.findByText('auditLog.title')).toBeInTheDocument();
    expect(screen.getByText('Folder#7')).toBeInTheDocument();
    expect(screen.getByText('admin@example.com')).toBeInTheDocument();
    expect(global.fetch).toHaveBeenCalledWith(expect.stringContaining('/admin/audit_logs?'));
  });

  it('applies audit log filters and re-fetches', async () => {
    await act(async () => { render(<AuditLogTab />); });
    await screen.findByText('auditLog.title');

    fireEvent.click(screen.getByText('auditLog.filters.apply'));

    await waitFor(() => {
      const calls = global.fetch.mock.calls.filter(([ url ]) => url.startsWith('/admin/audit_logs'));
      expect(calls.length).toBeGreaterThan(1);
    });
  });

  it('clears audit log filters', async () => {
    await act(async () => { render(<AuditLogTab />); });
    await screen.findByText('auditLog.title');

    fireEvent.click(screen.getByText('auditLog.filters.clear'));

    await waitFor(() => {
      const calls = global.fetch.mock.calls.filter(([ url ]) => url.startsWith('/admin/audit_logs'));
      expect(calls.length).toBeGreaterThan(1);
    });
  });

  it('shows an empty state message when no audit logs match', async () => {
    global.fetch = jest.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve({
      audit_logs: [], pagination: { page: 1, per_page: 25, total: 0, total_pages: 0 }, filter_options: { actions: [], auditable_types: [] },
    }) }));

    await act(async () => { render(<AuditLogTab />); });

    expect(await screen.findByText('auditLog.empty')).toBeInTheDocument();
  });

  it('renders SystemStatus main and switches tabs', async () => {
    await act(async () => { render(<SystemStatus incomingConfigs={{ address: 'smtp.example.com' }} />); });
    expect(screen.getByText('System Operations')).toBeInTheDocument();
    expect(await screen.findByText('Puma Rack')).toBeInTheDocument();
    fireEvent.click(screen.getByText('SMTP & Email Settings'));
    expect(await screen.findByText('SMTP Infrastructure Setup')).toBeInTheDocument();
    fireEvent.click(screen.getByText('Audit Trail'));
    expect(await screen.findByText('auditLog.title')).toBeInTheDocument();
  });
});
