import React from 'react';
import { render, screen, waitFor, fireEvent, act } from '@testing-library/react';

const mockNotify = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key, opts) => opts?.defaultValue || key }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

jest.mock('../../../../app/javascript/components/Shared/RichTextEditor', () => ({ value, onChange }) => (
  <textarea aria-label="Rich Text Editor" value={value} onChange={(e) => onChange(e.target.value)} />
));

import EmailEngineManager from '../../../../app/javascript/components/Admin/EmailEngineManager';

describe('EmailEngineManager', () => {
  beforeEach(() => {
    const _csrfMeta = document.head.querySelector('meta[name="csrf-token"]') || (() => { const m = document.createElement('meta'); m.name = 'csrf-token'; document.head.appendChild(m); return m; })(); _csrfMeta.content = 'token';
    global.fetch = jest.fn((url) => {
      if (url === '/admin/email_templates.json') {
        return Promise.resolve({ json: () => Promise.resolve({ email_templates: [{ id: 1, name: 'Welcome', subject: 'Hello', event_trigger: 'user_created', active: true }] }) });
      }
      if (url.startsWith('/admin/email_deliveries.json')) {
        return Promise.resolve({ json: () => Promise.resolve({ email_deliveries: [{ id: 2, recipient: 'alice@example.com', template_name: 'Welcome', status: 'sent', sent_at: 'Today' }] }) });
      }
      return Promise.resolve({ json: () => Promise.resolve({ success: true, message: 'ok' }) });
    });
  });

  it('renders without crashing', async () => {
    await act(async () => { render(<EmailEngineManager />); });
    expect(await screen.findByText('Communication Engine')).toBeInTheDocument();
    expect(await screen.findByText('Welcome')).toBeInTheDocument();
  });

  it('shows email configuration sections', async () => {
    await act(async () => { render(<EmailEngineManager />); });
    await screen.findByText('Welcome');
    fireEvent.click(screen.getByText('Event Mapping'));
    expect(screen.getByText('User Provisioned (Welcome)')).toBeInTheDocument();
    await act(async () => { fireEvent.click(screen.getByText('Outbox')); });
    await waitFor(() => expect(screen.getByText('alice@example.com')).toBeInTheDocument());
  });

  it('paginates the Templates tab client-side while keeping Event Mapping unaffected', async () => {
    const templates = Array.from({ length: 15 }, (_, i) => ({
      id: i + 1, name: `Template ${i}`, subject: `Subject ${i}`, event_trigger: 'user_created', active: true,
    }));

    global.fetch = jest.fn((url) => {
      if (url === '/admin/email_templates.json') {
        return Promise.resolve({ json: () => Promise.resolve({ email_templates: templates }) });
      }
      if (url.startsWith('/admin/email_deliveries.json')) {
        return Promise.resolve({ json: () => Promise.resolve({ email_deliveries: [] }) });
      }
      return Promise.resolve({ json: () => Promise.resolve({ success: true, message: 'ok' }) });
    });

    await act(async () => { render(<EmailEngineManager />); });

    expect(await screen.findByText('Template 0')).toBeInTheDocument();
    expect(screen.getByText('Template 9')).toBeInTheDocument();
    expect(screen.queryByText('Template 10')).not.toBeInTheDocument();
    expect(screen.getByText('Page 1 of 2')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /Next/ }));

    expect(await screen.findByText('Template 10')).toBeInTheDocument();
    expect(screen.queryByText('Template 0')).not.toBeInTheDocument();
    expect(screen.getByText('Page 2 of 2')).toBeInTheDocument();

    // Event Mapping tab must still see the full (unpaginated) template list.
    fireEvent.click(screen.getByText('Event Mapping'));
    expect(screen.getByText('User Provisioned (Welcome)')).toBeInTheDocument();
  });
});
