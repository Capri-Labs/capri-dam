import React from 'react';
import { render, screen } from '@testing-library/react';

const mockNotify = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

jest.mock('@mui/x-data-grid', () => {
  const React = require('react');
  return {
    DataGrid: ({ rows, columns, loading }) => (
      <div data-testid="report-export-grid">
        {loading ? <div>Loading...</div> : null}
        <table>
          <thead>
            <tr>{columns.map((col) => <th key={col.field}>{col.headerName}</th>)}</tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.id}>
                {columns.map((col) => {
                  const value = row[col.field];
                  return <td key={col.field}>{col.renderCell ? col.renderCell({ row, value }) : value}</td>;
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    ),
  };
});

import ReportExportTable from '../../../../app/javascript/components/Admin/ReportExportTable';

describe('ReportExportTable', () => {
  beforeEach(() => {
    global.fetch = jest.fn(() => Promise.resolve({
      json: () => Promise.resolve({
        snapshots: [{
          id: 1,
          created_at: '2026-07-01',
          report_name: 'Asset Audit',
          format: 'PDF',
          status: 'completed',
          download_url: '/download/report.pdf',
        }],
      }),
    }));
  });

  it('renders without crashing', async () => {
    render(<ReportExportTable refreshTrigger={0} />);
    expect(screen.getByText('Download Center (Recent Exports)')).toBeInTheDocument();
    expect(await screen.findByText('Asset Audit')).toBeInTheDocument();
  });

  it('shows a table with data', async () => {
    render(<ReportExportTable refreshTrigger={0} />);
    expect(await screen.findByText('Ready')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Save' })).toHaveAttribute('href', '/download/report.pdf');
    expect(screen.getByTestId('report-export-grid')).toBeInTheDocument();
  });
});
