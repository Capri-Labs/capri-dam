import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';

const mockNotify = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
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
    document.head.innerHTML = '<meta name="csrf-token" content="token" />';
    global.fetch = jest.fn((url) => {
      if (url === '/admin/email_templates.json') {
        return Promise.resolve({ json: () => Promise.resolve({ email_templates: [{ id: 1, name: 'Welcome', subject: 'Hello', event_trigger: 'user_created', active: true }] }) });
      }
      if (url === '/admin/email_deliveries.json') {
        return Promise.resolve({ json: () => Promise.resolve({ email_deliveries: [{ id: 2, recipient: 'alice@example.com', template_name: 'Welcome', status: 'sent', sent_at: 'Today' }] }) });
      }
      return Promise.resolve({ json: () => Promise.resolve({ success: true, message: 'ok' }) });
    });
  });

  it('renders without crashing', async () => {
    render(<EmailEngineManager />);
    expect(screen.getByText('Communication Engine')).toBeInTheDocument();
    expect(await screen.findByText('Welcome')).toBeInTheDocument();
  });

  it('shows email configuration sections', async () => {
    render(<EmailEngineManager />);
    await screen.findByText('Welcome');
    fireEvent.click(screen.getByText('Event Mapping (Settings)'));
    expect(screen.getByText('User Provisioned (Welcome)')).toBeInTheDocument();
    fireEvent.click(screen.getByText('Outbox & Audit Log'));
    await waitFor(() => expect(screen.getByText('alice@example.com')).toBeInTheDocument());
  });
});
