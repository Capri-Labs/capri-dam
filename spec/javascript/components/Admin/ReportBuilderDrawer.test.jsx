import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';

const mockNotify = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

import ReportBuilderDrawer from '../../../../app/javascript/components/Admin/ReportBuilderDrawer';

describe('Admin ReportBuilderDrawer', () => {
  beforeEach(() => {
    document.head.innerHTML = '<meta name="csrf-token" content="token" />';
    global.fetch = jest.fn((url) => {
      if (url === '/admin/reports.json') {
        return Promise.resolve({ json: () => Promise.resolve({ reports: [{ id: 1, name: 'Storage Report' }] }) });
      }
      return Promise.resolve({ json: () => Promise.resolve({ success: true }) });
    });
  });

  it('renders when open', async () => {
    render(<ReportBuilderDrawer open onClose={jest.fn()} onExportStarted={jest.fn()} />);
    expect(screen.getByText('Create Export')).toBeInTheDocument();
    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith('/admin/reports.json'));
  });

  it('shows form fields', async () => {
    render(<ReportBuilderDrawer open onClose={jest.fn()} onExportStarted={jest.fn()} />);
    expect(screen.getByText('1. Select Report Type')).toBeInTheDocument();
    expect(screen.getByText('2. Time Range')).toBeInTheDocument();
    expect(screen.getByText('3. Output Format')).toBeInTheDocument();
    expect(await screen.findByText('Generate Report')).toBeInTheDocument();
  });
});
